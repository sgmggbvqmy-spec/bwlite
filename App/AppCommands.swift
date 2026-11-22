// The menu bar: what its commands do in the main window.

import SwiftUI
import AppKit

/// What the menu bar can do in the main window. Only the unlocked vault window provides it (see VaultView), so
/// these menu items are greyed out while the vault is locked, like the Passwords app's.
struct VaultActions {
    var newPassword: () -> Void
    var showAll: () -> Void
    var showCodes: () -> Void
}

struct VaultActionsKey: FocusedValueKey {
    typealias Value = VaultActions
}

extension FocusedValues {
    var vaultActions: VaultActions? {
        get { self[VaultActionsKey.self] }
        set { self[VaultActionsKey.self] = newValue }
    }
}

/// The menu bar, arranged like the Passwords app's: Lock under the app menu, New Password… and New Window in File,
/// All and Codes at the top of View. (Show Sidebar, Enter Full Screen, Close and so on come from macOS.)
struct AppCommands: Commands {
    @ObservedObject var vault: Vault
    @FocusedValue(\.vaultActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Lock BwLite") { Task { await vault.lock() } }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(vault.state != .unlocked)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Password…") { actions?.newPassword() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(before: .sidebar) {
            Button { actions?.showAll() } label: { Label("All", systemImage: "key") }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(actions == nil)
            Button { actions?.showCodes() } label: { Label("TOTP", systemImage: "lock.badge.clock") }
                .keyboardShortcut("3", modifiers: .command)   // ⌘3 as in the original, where ⌘2 is Passkeys
                .disabled(actions == nil)
            Divider()
        }
    }
}
