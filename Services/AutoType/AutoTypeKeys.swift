// Typing a login into the app you were in: the keystrokes.
//
// Press ⌃⌥A in any app: a search box appears, pick a login, and BwLite types it into the app you were using
// (user name, Tab, password, Return), like KeePassXC's Auto-Type. It works in every browser and app because it
// only sends keystrokes; nothing goes through the clipboard.
//
//   ↩ user name, Tab, password, Return     ⌘↩ user name only     ⌥↩ password only     ⇧↩ the current code
//
// Sending keystrokes needs the Accessibility permission (System Settings > Privacy & Security > Accessibility);
// the panel asks for it the first time. If you start BwLite from Terminal rather than as an app, macOS
// attributes the permission to Terminal. The shortcut works only while BwLite is running (its window may be closed).

import Foundation
import ApplicationServices

nonisolated enum AutoTypeAction {
    case both, userName, password, code
}

/// Sends keystrokes to whichever app has the keyboard focus.
nonisolated enum KeyTyper {
    private static func post(keyCode: CGKeyCode, text: String? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = []   // don't carry over the ⌃⌥ of the shortcut if it is still held down
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.post(tap: .cghidEventTap)
        }
        usleep(5_000)
    }

    /// Types text character by character as Unicode, so it doesn't depend on the keyboard layout.
    static func type(_ text: String) {
        for character in text {
            switch character {
            case "\t": post(keyCode: 48)
            case "\n", "\r", "\r\n": post(keyCode: 36)
            default: post(keyCode: 0, text: String(character))
            }
        }
    }

    static func run(_ action: AutoTypeAction, user: String, password: String, totp: Totp?) {
        switch action {
        case .both:
            if !user.isEmpty {
                type(user)
                usleep(60_000)
                post(keyCode: 48)       // Tab
                usleep(60_000)
            }
            type(password)
            usleep(80_000)
            post(keyCode: 36)           // Return
        case .userName:
            type(user)
        case .password:
            type(password)
        case .code:
            if let totp { type(totp.code(at: Date())) }
        }
    }
}
