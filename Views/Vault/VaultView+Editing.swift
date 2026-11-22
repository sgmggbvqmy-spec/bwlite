// Edit mode, delete, restore, move and the changes on several items at once.

import SwiftUI
import AppKit

extension VaultView {
    // MARK: edit mode

    /// "Edit Websites" in the website menu: only logins have websites.
    func websiteEditor(for e: Entry) -> (() -> Void)? {
        guard e.kind == .login else { return nil }
        return { beginEdit(e, focusWebsite: true) }
    }

    /// The attachments card of the edit screen for an item.
    func attachmentEdits(for e: Entry) -> AttachmentEdits {
        AttachmentEdits(
            existing: e.attachments.filter { !removedAttachmentIds.contains($0.id) },
            pending: pendingAttachments,
            busy: editSaving,
            onAdd: { pendingAttachments += AttachmentController.chooseFiles(for: e.name).map { PendingAttachment(url: $0) } },
            onRemove: { removedAttachmentIds.insert($0.id) },
            onRemovePending: { p in pendingAttachments.removeAll { $0 == p } })
    }

    func beginEdit(_ e: Entry, focusWebsite: Bool) {
        if e.kind == .login { draft = EditDraft(e) } else { otherDraft = OtherDraft(e) }
        pendingAttachments = []
        removedAttachmentIds = []
        editingKind = e.kind
        editFocusWebsite = focusWebsite
        editError = nil
        editingId = e.id
    }

    /// Whether what is typed in the edit form can be saved (it needs a title).
    var canSaveEdit: Bool {
        editingKind == .login ? draft.canSave : otherDraft.canSave
    }

    /// Writes the changes to the server, then leaves edit mode. On failure the form stays as it is.
    func saveEdit() {
        guard let id = editingId, canSaveEdit, !editSaving else { return }
        editSaving = true
        let d = draft
        let o = otherDraft
        let isLogin = editingKind == .login
        let removals = Array(removedAttachmentIds)
        let additions = pendingAttachments
        Task { @MainActor in
            defer { editSaving = false }
            do {
                if isLogin {
                    try await vault.updateLogin(id: id,
                                                name: d.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                username: d.user, password: d.password,
                                                websites: d.websites.websites, notes: d.notes, totp: d.totp,
                                                fields: d.fields)
                } else {
                    try await vault.updateItem(id: id,
                                               name: o.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                               notes: o.notes, data: o.values, fields: o.fields)
                }
            } catch {
                editError = error.localizedDescription
                return
            }
            // The item itself is saved. Now the attachments: what was done is forgotten, what is left stays in the
            // form, so a second Save doesn't send a file twice.
            if !removals.isEmpty || !additions.isEmpty {
                let result = await vault.changeAttachments(itemId: id, remove: removals,
                                                           add: additions.map { (token: $0.id, url: $0.url) })
                removedAttachmentIds.subtract(result.removed)
                pendingAttachments.removeAll { result.added.contains($0.id) }
                if let failure = result.failure {
                    editError = "The item was saved, but not all changes to its attachments. " + failure
                    return
                }
            }
            editingId = nil
        }
    }

    func restore(_ e: Entry) {
        guard !editSaving else { return }
        editSaving = true
        Task { @MainActor in
            do {
                try await vault.restoreItem(id: e.id)
                selection.remove(e.id)
            } catch {
                editError = error.localizedDescription
            }
            editSaving = false
        }
    }

    func deleteForever(_ e: Entry) {
        guard !editSaving else { return }
        editSaving = true
        Task { @MainActor in
            do {
                try await vault.deleteItemForever(id: e.id)
                selection.remove(e.id)
            } catch {
                editError = error.localizedDescription
            }
            editSaving = false
        }
    }

    func deleteFolder(_ f: Folder) {
        guard !editSaving, let id = f.id else { return }
        editSaving = true
        Task { @MainActor in
            do {
                try await vault.deleteFolder(id: id)
                if folderFilter == id { folderFilter = "" }
            } catch {
                editError = error.localizedDescription
            }
            editSaving = false
        }
    }

    func delete(_ e: Entry) {
        guard !editSaving else { return }
        editSaving = true
        Task { @MainActor in
            do {
                try await vault.deleteItem(id: e.id)
                if editingId == e.id { editingId = nil }
                selection.remove(e.id)
            } catch {
                editError = error.localizedDescription
            }
            editSaving = false
        }
    }

    /// Runs one change on several items. A change that removes them from the list also drops them
    /// from the selection.
    func applyToEntries(_ entries: [Entry], clearsSelection: Bool,
                                _ change: @escaping @MainActor ([String]) async throws -> Void) {
        guard !editSaving, !entries.isEmpty else { return }
        editSaving = true
        let ids = entries.map { $0.id }
        Task { @MainActor in
            do {
                try await change(ids)
                if clearsSelection { selection.subtract(ids) }
            } catch {
                editError = error.localizedDescription
            }
            editSaving = false
        }
    }

    func moveEntries(_ entries: [Entry], to folderId: String?) {
        applyToEntries(entries, clearsSelection: false) { try await vault.moveItems(ids: $0, folderId: folderId) }
    }

    func restoreEntries(_ entries: [Entry]) {
        applyToEntries(entries, clearsSelection: true) { try await vault.restoreItems(ids: $0) }
    }

    func archiveEntries(_ entries: [Entry]) {
        applyToEntries(entries, clearsSelection: true) { try await vault.archiveItems(ids: $0) }
    }

    func unarchiveEntries(_ entries: [Entry]) {
        applyToEntries(entries, clearsSelection: true) { try await vault.unarchiveItems(ids: $0) }
    }

    func runBulk(_ request: BulkRequest) {
        switch request.kind {
        case .trash:
            applyToEntries(request.entries, clearsSelection: true) { try await vault.deleteItems(ids: $0) }
        case .forever:
            applyToEntries(request.entries, clearsSelection: true) { try await vault.deleteItemsForever(ids: $0) }
        }
    }

    var bulkTitle: String {
        guard let bulk else { return "" }
        let n = bulk.entries.count
        return bulk.kind == .forever ? "Delete \(n) Items Permanently?" : "Delete \(n) Items?"
    }

    func moveItem(_ e: Entry, to folderId: String?) {
        guard !editSaving else { return }
        editSaving = true
        Task { @MainActor in
            do {
                try await vault.moveItem(id: e.id, folderId: folderId)
            } catch {
                editError = error.localizedDescription
            }
            editSaving = false
        }
    }
}
