// The root view of a window: the login screen, the lock screen or the vault, depending on the state.

import SwiftUI
import AppKit

/// While the vault is locked: no title, no toolbar and a see-through title bar, so the window is one flat colour
/// with only the traffic lights, like the Passwords app's locked screen. When it unlocks, the window gets back
/// exactly what it had. SwiftUI re-configures its windows now and then, so this re-checks after every window update.
struct LockedWindowChrome: NSViewRepresentable {
    let locked: Bool

    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.locked = locked }

    final class ChromeView: NSView {
        private struct Saved {
            let titleVisibility: NSWindow.TitleVisibility
            let transparent: Bool
            let separator: NSTitlebarSeparatorStyle
            let toolbarVisible: Bool?
            let fullSize: Bool
        }

        var locked = false { didSet { apply() } }
        private var saved: Saved?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            NotificationCenter.default.removeObserver(self)
            if let newWindow {
                NotificationCenter.default.addObserver(self, selector: #selector(windowUpdated(_:)),
                                                       name: NSWindow.didUpdateNotification, object: newWindow)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        @objc private func windowUpdated(_ note: Notification) { apply() }

        private func apply() {
            guard let window else { return }
            if locked {
                if saved == nil {
                    saved = Saved(titleVisibility: window.titleVisibility,
                                  transparent: window.titlebarAppearsTransparent,
                                  separator: window.titlebarSeparatorStyle,
                                  toolbarVisible: window.toolbar?.isVisible,
                                  fullSize: window.styleMask.contains(.fullSizeContentView))
                }
                if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
                if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
                if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
                if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
                if window.toolbar?.isVisible == true { window.toolbar?.isVisible = false }
            } else if let s = saved {
                window.titleVisibility = s.titleVisibility
                window.titlebarAppearsTransparent = s.transparent
                window.titlebarSeparatorStyle = s.separator
                if !s.fullSize { window.styleMask.remove(.fullSizeContentView) }
                if let visible = s.toolbarVisible { window.toolbar?.isVisible = visible }
                saved = nil
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var vault: Vault

    var body: some View {
        Group {
            switch vault.state {
            case .checking:
                ProgressView("Checking…")
            case .problem:
                MessageView(title: "Something went wrong",
                            message: vault.error ?? "Unknown error.",
                            vault: vault)
            case .needsLogin:
                LoginView(vault: vault)
            case .locked:
                UnlockView(vault: vault)
            case .unlocked:
                VaultView(vault: vault)
            }
        }
        .frame(minWidth: 640, minHeight: 320)
        .background(LockedWindowChrome(locked: vault.state != .unlocked))
        .task {
            AutoType.shared.install(vault: vault)   // ⌃⌥A, see Services/AutoType
            await vault.startOnce()
        }
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
