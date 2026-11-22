// The sheet that makes a new item.

import SwiftUI
import AppKit

/// The "New Password" sheet, laid out like the macOS Passwords app: icon, title and rows, then the folder,
/// custom fields, Cancel / Save. A login also has an authentication key and any number of websites.
struct NewItemSheet: View {
    @ObservedObject var vault: Vault
    /// What is being made: a login, a card, an identity, ...
    let kind: ItemKind
    /// Called with the id of the new item.
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var user = ""
    @State private var password = ""
    @State private var authKey = ""
    @State private var sites = [WebsiteDraft()]
    /// Where the item goes: the folder being viewed to begin with.
    @State private var folder: String?
    @State private var notes = ""
    @State private var values: [String: String] = [:]   // the fields of the other kinds
    @State private var fields: [CustomField] = []
    @State private var saving = false
    @State private var generating = false
    @State private var showPassword = false
    @State private var showGenerator = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool

    init(vault: Vault, folderId: String?, kind: ItemKind = .login, onCreated: @escaping (String) -> Void) {
        self.vault = vault
        self.kind = kind
        self.onCreated = onCreated
        _folder = State(initialValue: folderId)
    }

    /// A key was typed that isn't a usable setup key.
    private var authKeyInvalid: Bool {
        let key = Totp.stored(from: authKey)
        return !key.isEmpty && Totp(key) == nil
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kind.missingField(in: values) == nil
            && !authKeyInvalid && !saving
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    Card {
                        VStack(spacing: 10) {
                            if kind == .login {
                                AppIcon(size: 54)
                            } else {
                                Avatar(name: title, size: 54, symbol: kind.icon)
                            }
                            TextField("Title", text: $title)
                                .textFieldStyle(.plain)
                                .font(.system(size: 22, weight: .bold))
                                .multilineTextAlignment(.center)
                                .focused($titleFocused)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                        .padding(.bottom, 14)
                        RowDivider()
                        if kind == .login { loginRows } else { SchemaFields(kind: kind, values: $values) }
                        if kind == .login || !kind.schema.isEmpty { RowDivider() }
                        TextField("Notes", text: $notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...10)
                            .padding(.vertical, 10.5)
                            .frame(maxWidth: .infinity, minHeight: kind == .secureNote ? 140 : 84, alignment: .topLeading)
                    }
                    if let hint = kind.requiredHint {
                        Text(hint).font(.callout).foregroundStyle(.secondary)
                    }
                    Card {
                        HStack(spacing: 12) {
                            Text("Folder")
                            Spacer(minLength: 12)
                            FolderPicker(folders: vault.folders, selection: $folder)
                        }
                        .padding(.vertical, 8)
                    }
                    CustomFieldsEditor(fields: $fields)
                }
                .padding(12)
            }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
            Divider()
            HStack(spacing: 12) {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 460, height: 580)
        // The generator button next to the password: pick a password or a passphrase there and use it here.
        .sheet(isPresented: $showGenerator) {
            GeneratorSheet(modes: [.password, .passphrase], onUse: { password = $0 })
        }
        .task {
            titleFocused = true
            // A new login gets a strong password filled in for you, like in Passwords.
            if kind == .login && password.isEmpty { await generate() }
        }
    }

    @ViewBuilder private var loginRows: some View {
        formRow("User Name") { TextField("user", text: $user) }
        RowDivider()
        formRow("Password") {
            HStack(spacing: 8) {
                iconButton(showPassword ? "eye.slash" : "eye", help: showPassword ? "Hide" : "Show") {
                    showPassword.toggle()
                }
                Button {
                    showGenerator = true
                } label: {
                    GeneratorIcon().foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open the generator")
                .disabled(generating)
                if showPassword {
                    TextField("password", text: $password)
                } else {
                    SecureField("password", text: $password)
                }
            }
        }
        RowDivider()
        formRow("Authentication Key") {
            TextField("Setup key or otpauth:// link", text: $authKey)
                .autocorrectionDisabled()
        }
        if authKeyInvalid {
            Text("This isn't a valid setup key.")
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 8)
        }
        RowDivider()
        WebsitesEditor(sites: $sites)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    /// "Label ........ field", right-aligned like the detail rows.
    private func formRow<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 12) {
            Text(label)
            field()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10.5)
    }

    /// Makes a new random password and puts it in the field.
    private func generate() async {
        generating = true
        defer { generating = false }
        do {
            password = try await VW.generatePassword()
        } catch {
            self.error = "Couldn't generate a password: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        error = nil
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // The folder could have been deleted (on another device) while this sheet was open.
        let target = vault.folders.contains { $0.id == folder } ? folder : nil
        Task { @MainActor in
            do {
                let id: String
                if kind == .login {
                    id = try await vault.createLogin(name: name, username: user, password: password,
                                                     websites: sites.websites, notes: notes, folderId: target,
                                                     totp: Totp.stored(from: authKey), fields: fields)
                } else {
                    id = try await vault.createItem(kind: kind, name: name, notes: notes, folderId: target,
                                                    data: values, fields: fields)
                }
                onCreated(id)
                saving = false
                dismiss()
            } catch {
                saving = false
                self.error = error.localizedDescription
            }
        }
    }
}
