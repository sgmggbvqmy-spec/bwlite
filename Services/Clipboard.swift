// Copying to the pasteboard, marked concealed and cleared again after 30 seconds.

import Foundation
import AppKit

enum Clipboard {
    /// The pasteboard's change count right after a secret was copied, to recognise it again.
    private static var secretCount: Int?

    /// Copies text. If `secret` is true, the item is marked as concealed (most clipboard managers
    /// skip it) and the clipboard is cleared after 30 seconds, or when the vault locks.
    static func copy(_ text: String, secret: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if secret {
            pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
        let count = pb.changeCount
        secretCount = secret ? count : nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            // Only clear if the clipboard still holds what we put there,
            // so we never wipe something the user copied afterwards.
            if NSPasteboard.general.changeCount == count {
                NSPasteboard.general.clearContents()
            }
        }
    }

    /// Empties the clipboard if it still holds a secret that BwLite copied (locking and logging out do this).
    /// Something the user copied afterwards is left alone.
    static func clearSecret() {
        defer { secretCount = nil }
        guard let count = secretCount, NSPasteboard.general.changeCount == count else { return }
        NSPasteboard.general.clearContents()
    }
}
