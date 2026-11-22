// Asks for the name of a new or renamed folder.

import SwiftUI
import AppKit

/// Asks for the name of a new folder, or for the new name of an existing one.
struct FolderNameSheet: View {
    @ObservedObject var vault: Vault
    /// The folder being renamed; nil makes a new folder.
    let renaming: Folder?
    /// Called with the id of the folder that was made or renamed.
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    init(vault: Vault, renaming: Folder? = nil, onDone: @escaping (String) -> Void) {
        self.vault = vault
        self.renaming = renaming
        self.onDone = onDone
        _name = State(initialValue: renaming?.name ?? "")
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != renaming?.name && !saving
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(renaming == nil ? "New Folder" : "Rename Folder").font(.headline)
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { save() }
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            Divider()
            HStack(spacing: 12) {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(renaming == nil ? "Create" : "Rename") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 340)
        .task { focused = true }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        error = nil
        let folderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                let id: String
                if let renaming, let folderId = renaming.id {
                    try await vault.renameFolder(id: folderId, name: folderName)
                    id = folderId
                } else {
                    id = try await vault.createFolder(name: folderName)
                }
                onDone(id)
                saving = false
                dismiss()
            } catch {
                saving = false
                self.error = error.localizedDescription
            }
        }
    }
}
