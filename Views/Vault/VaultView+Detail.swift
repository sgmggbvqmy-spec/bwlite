// The right column: the detail pane and its toolbar.

import SwiftUI
import AppKit

extension VaultView {
    /// What the Share button sends: name, user name and website. Never the password.
    var shareText: String {
        selectedEntry.map { sharingText(for: $0) } ?? ""
    }

    func sharingText(for e: Entry) -> String {
        var lines = [e.name]
        if let u = e.user, !u.isEmpty { lines.append("User name: \(u)") }
        lines += e.urls
        return lines.joined(separator: "\n")
    }

    /// Right column. Share and Edit sit in its toolbar, next to the search field, as in Passwords.
    var detailPane: some View {
        detailContent
            .navigationSplitViewColumnWidth(min: 220, ideal: 420)
            .toolbar { detailToolbar }
    }

    // MARK: toolbar of the right column

    /// Deleted with at most one item selected: nothing to offer up here (the item has its own Delete and
    /// Recover buttons under the details). The two toolbar items still stay, empty, so the toolbar is laid out
    /// as in the other lists and the Sort button of the middle column stays in its place.
    var detailToolbarBlank: Bool {
        folderFilter == Self.deleted && selectedEntries.count <= 1
    }

    /// In edit mode Cancel and Save take the place of Share and Edit, as in Passwords. In Deleted, several
    /// selected items have Delete and Recover here.
    @ToolbarContentBuilder var detailToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { firstDetailButton }
                .sharedBackgroundVisibility(detailToolbarBlank ? Visibility.hidden : Visibility.automatic)
            ToolbarItem(placement: .primaryAction) { secondDetailButton }
                .sharedBackgroundVisibility(detailToolbarBlank ? Visibility.hidden : Visibility.automatic)
        }
        if #unavailable(macOS 26.0) {
            ToolbarItem(placement: .primaryAction) { firstDetailButton }
            ToolbarItem(placement: .primaryAction) { secondDetailButton }
        }
    }

    @ViewBuilder var firstDetailButton: some View {
        if detailToolbarBlank {
            Color.clear.frame(width: 1, height: 1)
        } else if folderFilter == Self.deleted {
            Button {
                bulk = BulkRequest(kind: .forever, entries: selectedEntries)
                confirmBulk = true
            } label: {
                Text("Delete").foregroundStyle(Color.red)   // a toolbar doesn't colour the destructive role
            }
            .help("Delete the selected items permanently")
        } else if editingId != nil {
            Button("Cancel") { editingId = nil }
                .keyboardShortcut(.cancelAction)
                .disabled(editSaving)
        } else {
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(selectedEntry == nil)
            .help("Share name, user name and website (never the password)")
        }
    }

    @ViewBuilder var secondDetailButton: some View {
        if detailToolbarBlank {
            Color.clear.frame(width: 1, height: 1)
        } else if folderFilter == Self.deleted {
            Button("Recover") { restoreEntries(selectedEntries) }
                .help("Take the selected items out of Deleted")
        } else if editingId != nil {
            Button("Save") { saveEdit() }
                .foregroundStyle(Color.accentColor)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveEdit || editSaving)
        } else {
            Button("Edit") {
                if let e = selectedEntry { beginEdit(e, focusWebsite: false) }
            }
            .disabled(selectedEntry == nil)
        }
    }

    @ViewBuilder var detailContent: some View {
        if let e = selectedEntry {
            if folderFilter == Self.deleted {
                DetailView(entry: e, folderName: vault.folderName(for: e), onEditWebsites: nil,
                           deletedActions: DeletedActions(
                               recover: { restore(e) },
                               delete: { foreverTarget = e; confirmForever = true }),
                           onSaveAttachment: { attachments.save($0, of: e, vault: vault) },
                           downloadingAttachmentId: attachments.downloadingId).id(e.id)
            } else if editingId == e.id {
                if e.kind == .login {
                    EditView(draft: $draft, focusWebsite: editFocusWebsite,
                             onDelete: { deleteTarget = e; confirmDelete = true },
                             attachmentEdits: attachmentEdits(for: e))
                        .id("edit " + e.id)
                } else {
                    OtherEditView(draft: $otherDraft,
                                  onDelete: { deleteTarget = e; confirmDelete = true },
                                  attachmentEdits: attachmentEdits(for: e))
                        .id("edit " + e.id)
                }
            } else {
                DetailView(entry: e, folderName: vault.folderName(for: e),
                           onEditWebsites: websiteEditor(for: e),
                           onSaveAttachment: { attachments.save($0, of: e, vault: vault) },
                           downloadingAttachmentId: attachments.downloadingId).id(e.id)
            }
        } else if selectedEntries.count > 1 {
            ItemsSelectedView(count: selectedEntries.count)
        } else if let err = vault.error {
            Text(err).foregroundStyle(.red).padding()
        } else {
            Text("Select an item").foregroundStyle(.secondary)
        }
    }
}
