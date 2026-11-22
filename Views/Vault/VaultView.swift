// The main screen: folder tiles | items | details, like the macOS Passwords app. This file holds the state and the body;
// the parts are in the VaultView+*.swift files next to it.

import SwiftUI
import AppKit

struct VaultView: View {
    @ObservedObject var vault: Vault
    /// The selected items. Command-click adds or removes one, Shift-click selects a range, Command-A everything.
    @State var selection: Set<Entry.ID> = []
    /// Where a Shift-click range starts: the item clicked last.
    @State var anchor: Entry.ID?
    @State var query = ""
    @State var folderFilter = ""   // "" = all folders, "__none__" = no folder, otherwise a folder id
    @State var sortField: SortField = SortField.savedDefault
    @State var sortAscending = SortField.savedAscending
    // Watching the defaults, so a change in Settings reaches windows that are already open.
    @AppStorage(SortField.fieldKey) var defaultSortField = SortField.name.rawValue
    @AppStorage(SortField.ascendingKey) var defaultSortAscending = true
    // Edit mode: the item being edited (nil = not editing) and what has been typed so far.
    @State var editingId: String?
    @State var draft = EditDraft()              // a login being edited
    @State var otherDraft = OtherDraft(kind: .secureNote)   // any other kind being edited
    @State var editingKind = ItemKind.login
    @State var editFocusWebsite = false
    @State var editSaving = false
    @State var editError: String?
    @State var confirmDelete = false
    @State var deleteTarget: Entry?
    @Environment(\.openWindow) var openWindow
    @State var showNewItem = false
    @State var newItemKind = ItemKind.login
    // Attachments: clicking one saves a copy. In edit mode, files chosen and attachments marked for removal wait here
    // until Save.
    @StateObject var attachments = AttachmentController()
    @State var pendingAttachments: [PendingAttachment] = []
    @State var removedAttachmentIds: Set<String> = []
    @State var keyMonitor: Any?
    // Trash: the item whose permanent deletion is being confirmed.
    @State var foreverTarget: Entry?
    @State var confirmForever = false
    // Folders: the new-folder sheet, and the folder whose deletion is being confirmed.
    @State var showNewFolder = false
    // The generator sheet (button at the bottom left of the sidebar).
    @State var showGenerator = false
    // Which sidebar sections are folded away (remembered between launches).
    @AppStorage("sidebarTypeCollapsed") var typeCollapsed = false
    @AppStorage("sidebarFoldersCollapsed") var foldersCollapsed = false
    @AppStorage("sidebarHiddenCollapsed") var hiddenCollapsed = false
    @State var renameTarget: Folder?
    @State var folderTarget: Folder?
    @State var confirmFolderDelete = false

    // Several items at once: the change being confirmed.
    struct BulkRequest {
        enum Kind { case trash, forever }
        let kind: Kind
        let entries: [Entry]
    }
    @State var bulk: BulkRequest?
    @State var confirmBulk = false

    static let noFolder = "__none__"
    static let codes = "__codes__"
    static let deleted = "__deleted__"
    static let archive = "__archive__"
    static let typePrefix = "__type_"
    static func typeFilter(_ k: ItemKind) -> String { typePrefix + String(k.rawValue) }

    /// The kind of item chosen in the Type tiles, if one is.
    var typeFilterKind: ItemKind? {
        guard folderFilter.hasPrefix(Self.typePrefix) else { return nil }
        return ItemKind.allCases.first { Self.typeFilter($0) == folderFilter }
    }

    func inFolder(_ e: Entry) -> Bool {
        if let kind = typeFilterKind { return e.kind == kind }
        switch folderFilter {
        case "":
            return true
        case Self.noFolder:
            return e.folderId == nil
        case Self.codes:
            return e.totp != nil
        case Self.deleted, Self.archive:
            return true   // the list itself is the trash / the Archive
        default:
            // If the chosen folder no longer exists (e.g. removed by a sync), show everything.
            let exists = vault.folders.contains { $0.id == folderFilter }
            return exists ? e.folderId == folderFilter : true
        }
    }

    /// The items the list draws from: the trash, the Archive, or everything else.
    var source: [Entry] {
        switch folderFilter {
        case Self.deleted: return vault.deletedEntries
        case Self.archive: return vault.archivedEntries
        default: return vault.entries
        }
    }

    var filtered: [Entry] {
        source.filter { e in
            guard inFolder(e) else { return false }
            if query.isEmpty { return true }
            return e.name.localizedCaseInsensitiveContains(query)
                || (e.user ?? "").localizedCaseInsensitiveContains(query)
                || e.subtitle.localizedCaseInsensitiveContains(query)
                || e.urls.contains { url in url.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: statistics

    /// Number of logins per folder id ("" = no folder).
    var folderCounts: [String: Int] {
        Dictionary(grouping: vault.entries, by: { $0.folderId ?? "" }).mapValues { $0.count }
    }

    /// Title of the list column: the selected folder's name.
    var title: String {
        switch folderFilter {
        case "": return "All"
        case Self.noFolder: return "No Folder"
        case Self.codes: return "TOTP"
        case Self.deleted: return "Deleted"
        case Self.archive: return "Archive"
        default:
            if let kind = typeFilterKind { return kind.title }
            return vault.folders.first { $0.id == folderFilter }?.name ?? "All"
        }
    }

    /// Subtitle of the list column, e.g. "101 Items" (counts what the list currently shows).
    var subtitle: String {
        let n = filtered.count
        if folderFilter == Self.codes { return n == 1 ? "1 Verification Code" : "\(n) Verification Codes" }
        return n == 1 ? "1 Item" : "\(n) Items"
    }

    // MARK: layout — folder tiles | items | details, like the macOS Passwords app

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            itemList
        } detail: {
            detailPane
        }
        .searchable(text: $query, placement: .toolbar,
                    prompt: Text(folderFilter == Self.deleted ? "Search Deleted"
                                 : folderFilter == Self.archive ? "Search Archive" : "Search"))
        .sheet(isPresented: $showNewItem) {
            NewItemSheet(vault: vault, folderId: newItemFolderId, kind: newItemKind) { id in
                // Show the new item: leave any search that would hide it, and the trash, the Archive or a type
                // other than the new item's.
                query = ""
                if folderFilter == Self.deleted || folderFilter == Self.archive
                    || (typeFilterKind != nil && typeFilterKind != newItemKind) { folderFilter = "" }
                if !id.isEmpty {
                    selection = [id]
                    anchor = id
                }
            }
        }
        .sheet(isPresented: $showNewFolder) {
            FolderNameSheet(vault: vault) { id in
                // Look into the new folder.
                query = ""
                selection = []
                folderFilter = id
            }
        }
        .sheet(item: $renameTarget) { folder in
            FolderNameSheet(vault: vault, renaming: folder) { _ in }
        }
        .sheet(isPresented: $showGenerator) {
            GeneratorSheet()
        }
        .onValueChange(of: defaultSortField) { sortField = SortField(rawValue: $0) ?? .name }
        .onValueChange(of: defaultSortAscending) { sortAscending = $0 }
        .focusedSceneValue(\.vaultActions, VaultActions(
            newPassword: { newItemKind = .login; showNewItem = true },
            showAll: { folderFilter = "" },
            showCodes: { folderFilter = Self.codes }))
        .onValueChange(of: selectedEntry?.id) { id in
            // The edited item is gone from the list (another folder, a search): leave edit mode.
            if id != editingId { editingId = nil }
        }
        .alert("Couldn't Save", isPresented: Binding(get: { editError != nil },
                                                    set: { if !$0 { editError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editError ?? "")
        }
        .alert("Attachment", isPresented: Binding(get: { attachments.error != nil },
                                                  set: { if !$0 { attachments.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachments.error ?? "")
        }
        .alert("Delete “\(deleteTarget?.name ?? "this item")”?", isPresented: $confirmDelete,
               presenting: deleteTarget) { e in
            Button("Delete", role: .destructive) { delete(e) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It will be moved to the trash in Bitwarden.")
        }
        .alert("Delete “\(foreverTarget?.name ?? "this item")” Permanently?", isPresented: $confirmForever,
               presenting: foreverTarget) { e in
            Button("Delete Permanently", role: .destructive) { deleteForever(e) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert(bulkTitle, isPresented: $confirmBulk, presenting: bulk) { request in
            Button(request.kind == .forever ? "Delete Permanently" : "Delete", role: .destructive) { runBulk(request) }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.kind == .forever ? "This can't be undone." : "They will be moved to the trash in Bitwarden.")
        }
        .alert("Delete the Folder “\(folderTarget?.name ?? "")”?", isPresented: $confirmFolderDelete,
               presenting: folderTarget) { f in
            Button("Delete Folder", role: .destructive) { deleteFolder(f) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The items in it are kept and will have no folder.")
        }
    }

    /// New items go into the folder you are looking at (none with All, No Folder, a type, Archive and so on).
    var newItemFolderId: String? {
        vault.folders.contains { $0.id == folderFilter } ? folderFilter : nil
    }

    /// The selected items that are in the list on screen.
    var selectedEntries: [Entry] {
        filtered.filter { selection.contains($0.id) }
    }

    /// The item the detail pane shows: the selected one, when exactly one is selected.
    var selectedEntry: Entry? {
        let list = selectedEntries
        return list.count == 1 ? list.first : nil
    }
}
