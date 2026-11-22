// Edit mode of a login.

import SwiftUI
import AppKit

/// Everything the edit screen can change. It is filled from the item when you press Edit.
struct EditDraft {
    var title = ""
    var user = ""
    var password = ""
    var websites: [WebsiteDraft] = []
    /// The website icon the item had when editing began. Not changed while typing, so no half-typed address is asked for.
    var iconHost: String?
    var notes = ""
    var totp = ""        // authenticator key as stored: a base32 key or an otpauth:// link
    var fields: [CustomField] = []

    init() {}

    init(_ e: Entry) {
        title = e.name
        user = e.user ?? ""
        password = e.login?.password ?? ""
        websites = e.websites.map { WebsiteDraft(uri: $0.uri, match: $0.match) }
        iconHost = e.iconHost
        notes = e.notes ?? ""
        totp = e.login?.totp ?? ""
        fields = e.fields
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Grey rounded button used inside the edit cards ("Set Up Code...", "Delete").
struct FlatButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
    }
}

/// Edit mode of the detail pane, laid out like the Passwords app: separate cards for name and user name,
/// password, code, website and notes, then Delete. Cancel and Save are in the window toolbar.
struct EditView: View {
    @Binding var draft: EditDraft
    /// True when "Edit Websites" was chosen: the Website field starts with the keyboard focus.
    let focusWebsite: Bool
    let onDelete: () -> Void
    var attachmentEdits = AttachmentEdits()

    @State private var showCodeSetup = false
    @State private var showPassword = false
    @State private var showGenerator = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    VStack(spacing: 10) {
                        Avatar(name: draft.title, size: 60, host: draft.iconHost)
                        TextField("Title", text: $draft.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                    RowDivider()
                    fieldRow("User Name") { TextField("", text: $draft.user) }
                }
                Card {
                    fieldRow("Password") {
                        HStack(spacing: 8) {
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(showPassword ? "Hide" : "Show")
                            Button {
                                showGenerator = true
                            } label: {
                                GeneratorIcon().foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Open the generator")
                            if showPassword {
                                TextField("", text: $draft.password)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("", text: $draft.password)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
                codeCard
                Card {
                    WebsitesEditor(sites: $draft.websites, labelColor: .secondary, focusOnAppear: focusWebsite)
                    RowDivider()
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...12)
                        .padding(.vertical, 10.5)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
                }
                CustomFieldsEditor(fields: $draft.fields)
                AttachmentsEditor(edits: attachmentEdits)
                Card {
                    HStack {
                        Spacer()
                        Button("Delete", action: onDelete)
                            .buttonStyle(FlatButtonStyle(destructive: true))
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showCodeSetup) {
            CodeSetupSheet { draft.totp = $0 }
        }
        // The generator button next to the password: pick a password or a passphrase there and use it here.
        .sheet(isPresented: $showGenerator) {
            GeneratorSheet(modes: [.password, .passphrase], onUse: { draft.password = $0 })
        }
    }

    /// "Label ........ value": grey label, value you can type in, right-aligned.
    private func fieldRow<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            field()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10.5)
    }

    /// "Code ........ None" with a "Set Up Code..." button underneath.
    private var codeCard: some View {
        let totp = Totp(draft.totp)
        return Card {
            HStack(spacing: 12) {
                Text("Code").foregroundStyle(.secondary)
                Spacer(minLength: 16)
                if draft.totp.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else if let totp {
                    TotpValue(totp: totp).foregroundStyle(.secondary)
                } else {
                    Text("Unsupported").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10.5)
            RowDivider()
            HStack(spacing: 8) {
                Spacer()
                if draft.totp.isEmpty {
                    Button("Set Up Code...") { showCodeSetup = true }
                        .buttonStyle(FlatButtonStyle())
                } else {
                    Button("Remove Code") { draft.totp = "" }
                        .buttonStyle(FlatButtonStyle(destructive: true))
                    Button("Change Code...") { showCodeSetup = true }
                        .buttonStyle(FlatButtonStyle())
                }
            }
            .padding(.vertical, 10)
        }
    }
}
