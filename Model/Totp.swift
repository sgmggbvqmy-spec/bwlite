// Verification codes (TOTP) from an authenticator key.

import Foundation
import CryptoKit

/// A one-time-password key (the "Authenticator Key" of an item). Codes are computed here from the key
/// (RFC 6238), so showing them costs nothing and they keep ticking offline.
nonisolated struct Totp {
    private nonisolated enum Algorithm { case sha1, sha256, sha512 }

    private let key: Data
    private let algorithm: Algorithm
    let digits: Int
    let period: Int

    /// Reads what Bitwarden stores: a bare base32 key, or an `otpauth://totp/...` link that may also
    /// carry `period`, `digits` and `algorithm`. Steam keys (`steam://`) aren't supported.
    init?(_ stored: String?) {
        guard let stored else { return nil }
        let text = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var secret = text
        var seconds = 30
        var length = 6
        var alg = Algorithm.sha1
        if text.lowercased().hasPrefix("otpauth://") {
            // Parsed by hand: labels with spaces or odd characters make URLComponents give up.
            guard let q = text.firstIndex(of: "?") else { return nil }
            var found: String?
            for pair in text[text.index(after: q)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let name = kv[0].lowercased()
                let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                switch name {
                case "secret":
                    found = value
                case "period":
                    if let n = Int(value), n > 0 { seconds = n }
                case "digits":
                    if let n = Int(value), (6...8).contains(n) { length = n }
                case "algorithm":
                    switch value.lowercased() {
                    case "sha256": alg = .sha256
                    case "sha512": alg = .sha512
                    default: alg = .sha1
                    }
                default:
                    break
                }
            }
            guard let found else { return nil }
            secret = found
        } else if text.contains("://") {
            return nil
        }
        guard let data = Totp.base32(secret), !data.isEmpty else { return nil }
        key = data
        algorithm = alg
        digits = length
        period = seconds
    }

    /// What to store for a key someone typed or pasted: an otpauth:// link as it is, a bare key without the spaces
    /// it may have been typed in ("abcd efgh ...").
    static func stored(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("://") ? trimmed : trimmed.filter { !$0.isWhitespace }
    }

    private static func base32(_ s: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var out = Data()
        var buffer = 0
        var bits = 0
        for ch in s.uppercased() {
            if ch == " " || ch == "-" || ch == "=" { continue }
            guard let v = alphabet.firstIndex(of: ch) else { return nil }
            buffer = (buffer << 5) | v
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> bits) & 0xFF))
                buffer &= (1 << bits) - 1
            }
        }
        return out
    }

    /// The code valid at `date`, e.g. "570690".
    func code(at date: Date) -> String {
        var counter = UInt64(max(0, date.timeIntervalSince1970) / Double(period))
        var message = [UInt8](repeating: 0, count: 8)      // the counter, big-endian
        for i in stride(from: 7, through: 0, by: -1) {
            message[i] = UInt8(counter & 0xFF)
            counter >>= 8
        }
        let symmetric = SymmetricKey(data: key)
        let mac: [UInt8]
        switch algorithm {
        case .sha1:   mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetric))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: symmetric))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: symmetric))
        }
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let value = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        let number = String(value % modulus)
        return String(repeating: "0", count: max(0, digits - number.count)) + number
    }

    /// The code split in the middle, like Passwords shows it: "570 690".
    func formatted(at date: Date) -> String {
        let c = code(at: date)
        let half = (c.count + 1) / 2
        return String(c.prefix(half)) + " " + String(c.dropFirst(half))
    }

    /// Share of the current period that has passed: 0 right after a new code, 1 just before the next.
    func elapsed(at date: Date) -> Double {
        let p = Double(period)
        return max(0, date.timeIntervalSince1970).truncatingRemainder(dividingBy: p) / p
    }
}
