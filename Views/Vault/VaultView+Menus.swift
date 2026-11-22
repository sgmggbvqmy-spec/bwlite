// The right-click menus of an item.

import SwiftUI
import AppKit

extension VaultView {
    // MARK: right-click menu on an item, as in Passwords

    @ViewBuilder func rowMenu(for e: Entry) -> some View {
        // Right-clicking one of several selected items acts on all of them.
        let targets = selection.count > 1 && selection.contains(e.id) ? selectedEntries : [e]
        if targets.count > 1 {
            if folderFilter == Self.deleted {
                Button("Recover \(targets.count) Items") { restoreEntries(targets) }
                Divider()
                Button("Delete \(targets.count) Items Permanently…") {
                    bulk = BulkRequest(kind: .forever, entries: targets)
                    confirmBulk = true
                }
            } else {
                Menu {
                    Button("No Folder") { moveEntries(targets, to: nil) }
                    if !vault.folders.isEmpty { Divider() }
                    ForEach(vault.folders) { f in
                        Button(f.name) { moveEntries(targets, to: f.id) }
                    }
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                }
                if folderFilter == Self.archive {
                    Button("Unarchive \(targets.count) Items") { unarchiveEntries(targets) }
                } else {
                    Button("Archive \(targets.count) Items") { archiveEntries(targets) }
                }
                Divider()
                Button("Delete \(targets.count) Items…") {
                    bulk = BulkRequest(kind: .trash, entries: targets)
                    confirmBulk = true
                }
            }
        } else if folderFilter == Self.deleted {
            Button("Recover") { restore(e) }
            Divider()
            Button("Delete Permanently…") {
                foreverTarget = e
                confirmForever = true
            }
        } else {
            itemMenu(for: e)
        }
    }

    @ViewBuilder func itemMenu(for e: Entry) -> some View {
        Button("Open in New Window") { openWindow(value: e.id) }
        Divider()
        if e.kind == .login {
            Group {
                Button("Copy User Name") {
                    if let u = e.user, !u.isEmpty { Clipboard.copy(u, secret: false) }
                }
                .disabled((e.user ?? "").isEmpty)
                Button("Copy Password") {
                    if let p = e.login?.password, !p.isEmpty { Clipboard.copy(p, secret: true) }
                }
                .disabled((e.login?.password ?? "").isEmpty)
                Button("Copy Website") {
                    if let w = e.urls.first { Clipboard.copy(w, secret: false) }
                }
                .disabled(e.urls.isEmpty)
            }
            Divider()
        }
        Menu {
            Button("No Folder") { moveItem(e, to: nil) }
                .disabled(e.folderId == nil)
            if !vault.folders.isEmpty { Divider() }
            ForEach(vault.folders) { f in
                Button(f.name) { moveItem(e, to: f.id) }
                    .disabled(f.id == e.folderId)
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        if e.archived {
            Button("Unarchive") { unarchiveEntries([e]) }
        } else {
            Button("Archive") { archiveEntries([e]) }
        }
        Divider()
        Button("Delete…") {
            deleteTarget = e
            confirmDelete = true
        }
    }
}
