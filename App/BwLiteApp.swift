// BwLite — a minimal macOS client for a Vaultwarden server (a Bitwarden-compatible server you host yourself):
// list logins, show a password, copy it, add, edit, move and delete them, recover deleted ones, add, rename and delete folders, archive items, and keep cards, identities, secure notes, SSH keys, bank accounts, driver's licenses and passports, all with custom fields and attachments.
// A login has an authenticator key, any number of websites (each with its own URI match setting) and, if you like, the website's icon. Settings > Account changes the master password and the email, and logs out of all devices.
//
// BwLite talks to the server itself, with the same requests the Bitwarden apps send, and does the encryption
// in the app (PBKDF2 or Argon2id, then AES-256-CBC with HMAC-SHA256). No other program is needed. The server
// only ever sees encrypted data, and so does the copy of your vault kept on this Mac.
//
// Log in inside the app: Settings (Command-comma) sets the server, and the first screen asks for your email,
// master password and, if the account has one, an authenticator code.
//
// Private CA or self-signed certificate? macOS decides: open the certificate in Keychain Access and set it to
// "Always Trust", or choose the certificate file in Settings > Server Certificate.
//
// Auto-lock: Settings has a switch and a number of minutes; BwLite locks itself after that long unused (on, 15 minutes at first).
// Touch ID: an optional switch in Settings; after one unlock with the master password, clicking the fingerprint on the lock screen unlocks it again.
//
// Offline use: unlocking, listing, showing and copying only read the local, encrypted copy of the vault.
// Only the Sync button, and saving a change, need the network. Log in and sync at least once while online.
//
// Not supported: accounts with the newer "V2" encryption, two-step methods other than an authenticator app,
// single sign-on accounts, and the official Bitwarden cloud.
//
// Auto-Type: press Control-Option-A in any app, pick a login, and BwLite types it for you. It needs the
// Accessibility permission (asked for the first time). See Services/AutoType.
//
// Build: in Xcode, or with swiftc (see the GitHub workflow).

import SwiftUI
import AppKit

@main
struct BwLiteApp: App {
    // One vault for every window: the main window and the windows opened from the right-click menu.
    @StateObject private var vault = Vault()

    init() {
        // An executable launched straight from the terminal isn't a "regular" app by default;
        // this line is needed for it to receive keyboard focus.
        NSApplication.shared.setActivationPolicy(.regular)
        #if AUTOFILL
        AutoFillHost.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup("BwLite", id: "main") { ContentView(vault: vault) }
            .defaultSize(width: 1100, height: 700)
            .commands { AppCommands(vault: vault) }
        WindowGroup("Item", for: String.self) { id in
            ItemWindow(vault: vault, id: id.wrappedValue)
        }
        .defaultSize(width: 420, height: 560)
        // Adds "Settings…" (⌘,) to the app menu.
        Settings { SettingsView(vault: vault) }
    }
}
