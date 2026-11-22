// Settings (⌘,): General, Server and Account.

import SwiftUI
import AppKit

/// What the Account tab can change. Each needs the current master password and ends the login on this Mac.
enum AccountChange: String, Identifiable {
    case password, email, stamp
    var id: String { rawValue }
}

/// Settings (⌘,): General (sorting, auto-lock, Touch ID), Server (which server, its certificate) and Account
/// (who is logged in, and changing the master password and the email, or logging out everywhere).
struct SettingsView: View {
    @ObservedObject var vault: Vault
    @AppStorage("email") private var email = ""
    @AppStorage(SortField.fieldKey) private var defaultSortField = SortField.name.rawValue
    @AppStorage(SortField.ascendingKey) private var defaultSortAscending = true
    @State private var server = ""
    @State private var working = false
    @State private var message: String?
    @State private var confirmLogout = false
    @State private var accountChange: AccountChange?
    /// Certificate file for a server with a self-signed certificate ("" = none).
    @AppStorage(VW.caKey) private var caPath = ""
    @AppStorage(VW.autoLockEnabledKey) private var autoLockEnabled = true
    @AppStorage(VW.autoLockMinutesKey) private var autoLockMinutes = VW.autoLockDefaultMinutes
    @AppStorage(VW.touchIDKey) private var touchIDEnabled = false
    @AppStorage(VWIcons.showKey) private var showIcons = true

    /// The server can only be changed while nobody is logged in.
    private var loggedIn: Bool { vault.state == .locked || vault.state == .unlocked }

    private var serverChanged: Bool {
        Vault.normalizedServer(server) != Vault.normalizedServer(vault.serverURL)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            serverTab
                .tabItem { Label("Server", systemImage: "server.rack") }
            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 480)
        .onAppear { server = vault.serverURL }
        .onValueChange(of: vault.serverURL) { server = $0 }
        .alert("Log Out of BwLite?", isPresented: $confirmLogout) {
            Button("Log Out", role: .destructive) {
                Task { message = await vault.logout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your vault and your login from this Mac. You will need your master password to log in again.")
        }
        .sheet(item: $accountChange) { change in
            AccountChangeSheet(vault: vault, change: change)
        }
    }

    private var generalTab: some View {
        Form {
            Section("Default Sort") {
                Picker("Sort By", selection: $defaultSortField) {
                    ForEach(SortField.allCases) { f in
                        Text(f.rawValue).tag(f.rawValue)
                    }
                }
                Picker("Order", selection: $defaultSortAscending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                Text("Used for every new window. The Sort button above the list changes the order of that window only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Auto-Lock") {
                Toggle("Lock automatically", isOn: $autoLockEnabled)
                LabeledContent("Lock after") {
                    HStack(spacing: 6) {
                        TextField("", value: $autoLockMinutes, format: .number)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                        Stepper("", value: $autoLockMinutes, in: VW.autoLockMinuteRange)
                            .labelsHidden()
                        Text(autoLockMinutes == 1 ? "minute" : "minutes")
                    }
                }
                .disabled(!autoLockEnabled)
                .onValueChange(of: autoLockMinutes) { minutes in
                    let clamped = min(max(minutes, VW.autoLockMinuteRange.lowerBound), VW.autoLockMinuteRange.upperBound)
                    if clamped != minutes { autoLockMinutes = clamped }
                }
                Text(autoLockEnabled
                     ? "BwLite locks itself when you haven't used it for this many minutes (1 to 1440)."
                     : "BwLite stays unlocked until you lock it or quit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Website Icons") {
                Toggle("Show website icons", isOn: $showIcons)
                    .onValueChange(of: showIcons) { _ in IconStore.shared.clear() }
                Text("Icons come through your Vaultwarden server, which looks them up on the websites, so the server learns which sites you have logins for. They are kept in memory only and forgotten when BwLite locks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if TouchID.available {
                Section("Touch ID") {
                    Toggle("Unlock with Touch ID", isOn: $touchIDEnabled)
                        .onValueChange(of: touchIDEnabled) { _ in Task { await vault.syncTouchID() } }
                    Text(touchIDEnabled && !vault.touchIDKeySaved
                         ? "Unlock once with your master password to finish setting this up."
                         : "Unlocks BwLite with your fingerprint instead of the master password. For that, the vault key is kept in your login keychain, which is less safe than typing the password each time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var serverTab: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $server, prompt: Text("https://vault.example.com"))
                    .disabled(loggedIn || working)
                    .onSubmit { saveServer() }
                HStack {
                    Text(loggedIn ? "Log out to change the server."
                                  : "The address of your Vaultwarden server.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    Button("Save") { saveServer() }
                        .disabled(loggedIn || working || !serverChanged)
                }
            }
            Section("Server Certificate") {
                HStack {
                    TextField("Certificate", text: $caPath, prompt: Text("None"))
                        .autocorrectionDisabled()
                    Button("Choose…") { chooseCertificate() }
                    if !caPath.isEmpty {
                        Button("Clear") { caPath = "" }
                    }
                }
                Text(certificateNote)
                    .font(.callout)
                    .foregroundStyle(certificateMissing ? Color.red : Color.secondary)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accountTab: some View {
        Form {
            Section("Account") {
                if loggedIn {
                    LabeledContent("Email", value: vault.userEmail ?? email)
                    LabeledContent("Server", value: vault.serverDisplay)
                    Button("Log Out…", role: .destructive) { confirmLogout = true }
                    Text("Log Out removes your vault and your login from this Mac. Vaultwarden has no way to end just this Mac's login on the server: only Log Out of All Devices below does that, for every device at once.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Email", text: $email, prompt: Text("name@example.com"))
                    Text("You enter your master password on the login screen of the BwLite window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if loggedIn {
                Section("Login Details") {
                    Button("Change Master Password…") { accountChange = .password }
                    Button("Change Email…") { accountChange = .email }
                }
                .disabled(vault.state != .unlocked)
                Section("Devices") {
                    Button("Log Out of All Devices…", role: .destructive) { accountChange = .stamp }
                        .disabled(vault.state != .unlocked)
                }
                Text(vault.state == .unlocked
                     ? "Each of these asks for your master password. Afterwards you log in again here, and on every other device."
                     : "Unlock BwLite to change these.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var certificateMissing: Bool {
        let t = caPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !FileManager.default.fileExists(atPath: (t as NSString).expandingTildeInPath)
    }

    private var certificateNote: String {
        if caPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "For a server with a private CA or a self-signed certificate: set the certificate to Always Trust in Keychain Access, or choose its file here."
        }
        return certificateMissing ? "This file does not exist."
                                  : "This certificate is trusted in addition to the usual ones."
    }

    private func chooseCertificate() {
        let panel = NSOpenPanel()
        panel.title = "Choose Certificate"
        panel.message = "Select the certificate file of your server in PEM format (.pem or .crt)."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            caPath = url.path
        }
    }

    private func saveServer() {
        guard !loggedIn, !working, serverChanged else { return }
        working = true
        message = nil
        Task {
            message = await vault.setServer(server)
            working = false
        }
    }
}
