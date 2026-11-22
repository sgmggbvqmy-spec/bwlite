// Attachments: download, add and remove.

import SwiftUI
import AppKit
import Combine

/// What clicking an attachment does: ask where to put a copy, download it and write it there. Also asks which files
/// to attach. The last error is kept for an alert.
@MainActor
final class AttachmentController: ObservableObject {
    /// Something is being downloaded, sent or removed.
    @Published private(set) var busy = false
    /// The attachment being downloaded, to show a spinner in its row.
    @Published private(set) var downloadingId: String?
    @Published var error: String?

    func save(_ a: ItemAttachment, of e: Entry, vault: Vault) {
        guard !busy else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = a.fileName
        panel.canCreateDirectories = true
        panel.message = "Save a copy of this attachment"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let itemId = e.id, attachmentId = a.id
        run(downloading: a.id) {
            let file = try await vault.downloadAttachment(itemId: itemId, attachmentId: attachmentId)
            try file.data.write(to: url, options: .atomic)
        }
    }

    /// Asks which files to attach to an item. Nothing is sent yet: that happens when the item is saved.
    static func chooseFiles(for itemName: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        panel.message = "Choose the files to attach to “\(itemName)”"
        return panel.runModal() == .OK ? panel.urls : []
    }

    private func run(downloading id: String? = nil, _ work: @escaping @MainActor @Sendable () async throws -> Void) {
        busy = true
        downloadingId = id
        error = nil
        Task { @MainActor in
            do { try await work() } catch { self.error = error.localizedDescription }
            busy = false
            downloadingId = nil
        }
    }
}

/// A file chosen in the edit screen. It is sent when the item is saved.
struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let size: Int64

    init(url: URL) {
        self.url = url
        size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    var fileName: String { url.lastPathComponent }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

/// What the attachments card of the edit screen shows and does. Nothing reaches the server until Save: removing marks
/// an attachment, adding only remembers the file.
struct AttachmentEdits {
    /// Attached already, and not marked for removal.
    var existing: [ItemAttachment] = []
    /// Chosen, not sent yet.
    var pending: [PendingAttachment] = []
    /// The item is being saved: no changes now.
    var busy = false
    var onAdd: () -> Void = {}
    var onRemove: (ItemAttachment) -> Void = { _ in }
    var onRemovePending: (PendingAttachment) -> Void = { _ in }
}

/// The attachments card of the edit screen: a row per file with a minus button, and "Add Attachment…". The changes are
/// made on the server when the item is saved, and dropped on Cancel.
struct AttachmentsEditor: View {
    let edits: AttachmentEdits

    var body: some View {
        Card {
            ForEach(edits.existing) { a in
                row(name: a.fileName, size: a.sizeText, isNew: false) { edits.onRemove(a) }
            }
            ForEach(edits.pending) { p in
                row(name: p.fileName, size: p.sizeText, isNew: true) { edits.onRemovePending(p) }
            }
            HStack(spacing: 8) {
                if edits.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Add Attachment…", action: edits.onAdd)
                    .buttonStyle(FlatButtonStyle())
                    .disabled(edits.busy)
            }
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder private func row(name: String, size: String, isNew: Bool, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: remove) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(isNew ? "Don't attach this file" : "Remove this attachment")
            .disabled(edits.busy)
            Text(name).lineLimit(1).truncationMode(.middle)
            if isNew { Text("New").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 16)
            Text(size).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10.5)
        RowDivider()
    }
}
