// The global shortcut (⌃⌥A) and what it does.

import SwiftUI
import AppKit
import Carbon.HIToolbox   // the global ⌃⌥A shortcut (Auto-Type)
import ApplicationServices

// The hotkey callback must be a plain C-compatible function, so it lives at file level and hops to the main actor.
private nonisolated func autoTypeHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                                               _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in AutoType.shared.toggle() }
    return noErr
}

@MainActor
final class AutoType {
    static let shared = AutoType()

    /// The shortcut: ⌃⌥A. kVK_ANSI_A is the physical A key, whatever the keyboard layout.
    private let hotKeyCode = UInt32(kVK_ANSI_A)
    private let hotKeyModifiers = UInt32(controlKey | optionKey)

    private var vault: Vault?
    private var hotKey: EventHotKeyRef?
    private var panel: AutoTypePanel?
    private var model: AutoTypeModel?
    private var keyMonitor: Any?
    /// The app that had the keyboard focus when the shortcut was pressed: where the keystrokes go.
    private var target: NSRunningApplication?

    /// Registers the shortcut. Safe to call more than once.
    func install(vault: Vault) {
        self.vault = vault
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        _ = InstallEventHandler(GetApplicationEventTarget(), autoTypeHotKeyHandler, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: 0x4277_4C74, id: 1)   // "BwLt"
        let status = RegisterEventHotKey(hotKeyCode, hotKeyModifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("BwLite Auto-Type: the ⌃⌥A shortcut is unavailable (error \(status))") }
    }

    func toggle() {
        if panel != nil { close() } else { show() }
    }

    /// Asks macOS for the Accessibility permission (shows the system prompt).
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Brings BwLite's own window forward, reopening it when it was closed.
    static func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }), Bundle.main.bundlePath.hasSuffix(".app") {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
        AutoType.shared.close()
    }

    private func show() {
        guard let vault else { return }
        target = NSWorkspace.shared.frontmostApplication

        let model = AutoTypeModel(vault: vault)
        self.model = model

        let size = NSSize(width: 560, height: 400)
        let panel = AutoTypePanel(size: size)
        panel.contentView = NSHostingView(rootView: AutoTypeView(model: model, vault: vault,
                                                                 onRun: { [weak self] in self?.run($0) }))
        panel.onResign = { [weak self] in
            // Clicking elsewhere or switching apps dismisses the panel. Deferred: we're inside resignKey.
            Task { @MainActor in self?.close() }
        }

        // Center horizontally, in the upper part of the screen the mouse is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - f.height * 0.18 - size.height))
        }
        self.panel = panel
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        panel?.onResign = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil   // drops the search text and the copy of the list
    }

    /// Up/Down move the selection, Return types, Esc closes. Not while an input method is composing text.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let panel, panel.isKeyWindow, let model else { return event }
        if event.keyCode == 53 {   // Esc
            close()
            return nil
        }
        guard vault?.state == .unlocked else { return event }   // while locked, Return belongs to the password field
        if (panel.firstResponder as? NSTextInputClient)?.hasMarkedText() == true { return event }
        switch event.keyCode {
        case 125, 126:   // down, up
            model.move(event.keyCode == 125 ? 1 : -1)
            return nil
        case 36, 76:     // Return, keypad Enter
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) { run(.userName) }
            else if flags.contains(.option) { run(.password) }
            else if flags.contains(.shift) { run(.code) }
            else { run(.both) }
            return nil
        default:
            return event
        }
    }

    /// Closes the panel, then types the selected login into the app that had the focus.
    private func run(_ action: AutoTypeAction) {
        guard let model, let entry = model.current, let login = entry.login else { return }
        guard AXIsProcessTrusted() else {
            model.trusted = false   // the panel shows a banner with an "Allow…" button
            return
        }
        let user = login.username ?? ""
        let password = login.password ?? ""
        let totp = entry.totp
        let target = self.target
        close()
        Task {
            // Let the panel go away and the focus return to where it was.
            try? await Task.sleep(for: .milliseconds(150))
            if let target, !target.isActive {
                if #available(macOS 14.0, *) { target.activate() } else { target.activate(options: []) }
                try? await Task.sleep(for: .milliseconds(250))
            }
            await Task.detached(priority: .userInitiated) {
                KeyTyper.run(action, user: user, password: password, totp: totp)
            }.value
        }
    }
}
