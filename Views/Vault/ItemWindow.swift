// One item in a window of its own.

import SwiftUI
import AppKit

/// A window with one item's details ("Open in New Window"). It shows nothing once the vault is locked.
struct ItemWindow: View {
    @ObservedObject var vault: Vault
    let id: String?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var attachments = AttachmentController()

    private var entry: Entry? {
        guard vault.state == .unlocked, let id else { return nil }
        return (vault.entries + vault.archivedEntries).first { $0.id == id }
    }

    var body: some View {
        Group {
            if let e = entry {
                DetailView(entry: e, folderName: vault.folderName(for: e), onEditWebsites: nil,
                           onSaveAttachment: { attachments.save($0, of: e, vault: vault) },
                           downloadingAttachmentId: attachments.downloadingId)
                    .navigationTitle(e.name)
            } else {
                Text(vault.state == .unlocked ? "This item is no longer available." : "The vault is locked.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 300, minHeight: 300)
        .alert("Attachment", isPresented: Binding(get: { attachments.error != nil },
                                                  set: { if !$0 { attachments.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachments.error ?? "")
        }
        // Windows restored at launch, or left open while the vault locks, close instead of lingering.
        .onAppear { if vault.state != .unlocked { dismiss() } }
        .onValueChange(of: vault.state) { s in if s != .unlocked { dismiss() } }
    }
}
