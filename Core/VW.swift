// Settings kept in the user defaults (server, certificate, auto-lock, Touch ID) and the device id.

import Foundation

/// Settings keys and small helpers shared by the core and the Settings window.
nonisolated enum VW {
    /// UserDefaults key of the certificate file chosen in Settings (the key kept from the earlier bw version,
    /// so a chosen file survives the update).
    static let caKey = "bwCACert"
    static let serverKey = "vwServer"
    private static let deviceKey = "vwDeviceId"

    /// The certificate file chosen in Settings, or "" for none.
    static var customCACert: String {
        let t = (UserDefaults.standard.string(forKey: caKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : (t as NSString).expandingTildeInPath
    }

    /// UserDefaults keys of the auto-lock switch and of the time in minutes.
    static let autoLockEnabledKey = "autoLockEnabled"
    static let autoLockMinutesKey = "autoLockMinutes"
    static let autoLockDefaultMinutes = 15
    static let autoLockMinuteRange = 1...1440

    /// UserDefaults key of the "Unlock with Touch ID" switch.
    static let touchIDKey = "touchIDEnabled"

    /// How long BwLite may go unused before it locks itself; nil when auto-lock is switched off.
    static var autoLockMinutes: Int? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: autoLockEnabledKey) as? Bool ?? true else { return nil }
        let minutes = defaults.object(forKey: autoLockMinutesKey) as? Int ?? autoLockDefaultMinutes
        return autoLockMinuteRange.contains(minutes) ? minutes : autoLockDefaultMinutes
    }

    /// The server chosen in Settings while nobody is logged in ("" = none yet).
    static var savedServer: String { UserDefaults.standard.string(forKey: serverKey) ?? "" }

    /// "vault.example.com/" -> "https://vault.example.com". Empty stays empty.
    static func normalizedServer(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if !t.contains("://") { t = "https://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }

    /// Why a server address can't be used, or nil when it can.
    static func serverProblem(_ url: String) -> String? {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = u.host?.lowercased(), !host.isEmpty else {
            return "That isn't a valid server address. Use something like https://vault.example.com."
        }
        if host == "bitwarden.com" || host.hasSuffix(".bitwarden.com") || host == "bitwarden.eu" || host.hasSuffix(".bitwarden.eu") {
            return "BwLite talks to Vaultwarden servers directly. The official Bitwarden cloud isn't supported."
        }
        return nil
    }

    /// An id for this Mac that the server remembers as a device (it's what the "new device" notice is about).
    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey), !id.isEmpty { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    /// A new random password: 20 letters and digits (no symbols, so almost every site accepts it), with at least
    /// one capital letter, one small letter and one digit.
    static func generatePassword() async throws -> String {
        let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let lower = Array("abcdefghijklmnopqrstuvwxyz")
        let digits = Array("0123456789")
        let all = upper + lower + digits
        func pick(_ set: [Character]) -> Character { set[randomIndex(below: set.count)] }
        var chars: [Character] = [pick(upper), pick(lower), pick(digits)]
        while chars.count < 20 { chars.append(pick(all)) }
        for i in stride(from: chars.count - 1, to: 0, by: -1) {   // Fisher-Yates shuffle
            chars.swapAt(i, randomIndex(below: i + 1))
        }
        return String(chars)
    }

    /// A uniformly distributed number below `n` (at most 256), without modulo bias.
    private static func randomIndex(below n: Int) -> Int {
        let limit = 256 - (256 % n)
        while true {
            let byte = Int(VWPrim.random(1)[0])
            if byte < limit { return byte % n }
        }
    }
}
