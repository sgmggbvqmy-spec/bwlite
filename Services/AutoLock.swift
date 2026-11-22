// When BwLite was last used, for the auto-lock.

import Foundation

/// When BwLite was last used: a key press, a click or a scroll in one of its windows (the Auto-Type panel
/// included), or unlocking. Safe to call from any thread.
nonisolated final class VWActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date()

    func touch() {
        lock.lock()
        last = Date()
        lock.unlock()
    }

    func idleSeconds() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(last)
    }
}
