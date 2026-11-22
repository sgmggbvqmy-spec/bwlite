// The Bitwarden encryption: key derivation settings, the master key, EncString (AES-256-CBC + HMAC-SHA256), RSA.

import Foundation
import CryptoKit

/// The key-derivation settings of an account, as the server reports them.
nonisolated struct VWKDF: Codable, Equatable {
    var type: Int            // 0 = PBKDF2-SHA256, 1 = Argon2id
    var iterations: Int
    var memory: Int?         // MiB, Argon2id only
    var parallelism: Int?    // Argon2id only

    /// As the account-change requests carry it.
    var json: [String: Any] {
        ["kdfType": type, "iterations": iterations,
         "memory": memory.map { $0 as Any } ?? NSNull(), "parallelism": parallelism.map { $0 as Any } ?? NSNull()]
    }
}

nonisolated enum VWCrypto {
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The 32-byte master key. The server never sees it.
    static func masterKey(password: String, email: String, kdf: VWKDF) throws -> Data {
        let salt = Data(normalizedEmail(email).utf8)
        var passwordBytes = Data(password.utf8)
        defer { passwordBytes.wipe() }
        switch kdf.type {
        case 0:
            // Bounds so a wrong or hostile answer can't make this hang or be weakened to nothing.
            guard (5_000...10_000_000).contains(kdf.iterations) else {
                throw VWError.failed("The server reports an unusual PBKDF2 setting (\(kdf.iterations) iterations), so BwLite stops.")
            }
            return try VWPrim.pbkdf2(password: passwordBytes, salt: salt, iterations: kdf.iterations)
        case 1:
            let t = kdf.iterations
            let m = kdf.memory ?? 64
            let p = kdf.parallelism ?? 4
            guard (1...100).contains(t), (8...1024).contains(m), (1...64).contains(p) else {
                throw VWError.failed("The server reports an unusual Argon2id setting (t=\(t), m=\(m) MiB, p=\(p)), so BwLite stops.")
            }
            // Bitwarden salts Argon2id with SHA-256 of the email.
            return Argon2id.hash(password: passwordBytes, salt: Data(SHA256.hash(data: salt)),
                                 iterations: t, memoryKiB: m * 1024, parallelism: p, length: 32)
        default:
            throw VWError.failed("This account uses a key derivation method (\(kdf.type)) that BwLite doesn't know.")
        }
    }

    /// What the server gets as the password: PBKDF2(masterKey, password, 1 round), base64.
    static func masterHash(masterKey: Data, password: String) throws -> String {
        var salt = Data(password.utf8)
        defer { salt.wipe() }
        return try VWPrim.pbkdf2(password: masterKey, salt: salt, iterations: 1).base64EncodedString()
    }

    /// Splits the master key into the key pair that protects the account key (HKDF-Expand "enc" and "mac").
    static func stretch(_ masterKey: Data) -> VWKey {
        let prk = SymmetricKey(data: masterKey)
        func expand(_ info: String) -> Data {
            let key = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data(info.utf8), outputByteCount: 32)
            return key.withUnsafeBytes { Data($0) }
        }
        var enc = expand("enc"), mac = expand("mac")
        defer { enc.wipe(); mac.wipe() }
        return VWKey(enc: enc, mac: mac)
    }

    private static func mac(_ key: VWKey, _ iv: Data, _ ciphertext: Data) -> Data {
        key.withMac { raw in
            var h = HMAC<SHA256>(key: SymmetricKey(data: raw))
            h.update(data: iv)
            h.update(data: ciphertext)
            return Data(h.finalize())
        }
    }

    private static func sameBytes(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    /// Decrypts an EncString of type 2: `2.<iv>|<ciphertext>|<mac>` (AES-256-CBC, HMAC-SHA256 over iv + ciphertext).
    static func decrypt(_ text: String, with key: VWKey) throws -> Data {
        guard let dot = text.firstIndex(of: "."), let type = Int(text[..<dot]) else {
            throw VWError.failed("A value from the server isn't in the expected encrypted format.")
        }
        guard type == 2 else {
            throw VWError.failed(type == 7
                ? "This account uses the newer \"V2\" encryption of Bitwarden (EncString type 7). BwLite can't read it yet."
                : "A value uses an encryption type (\(type)) that BwLite doesn't support.")
        }
        let parts = text[text.index(after: dot)...].split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let iv = Data(base64Encoded: String(parts[0])),
              let ciphertext = Data(base64Encoded: String(parts[1])),
              let tag = Data(base64Encoded: String(parts[2])),
              iv.count == 16, tag.count == 32 else {
            throw VWError.failed("A value from the server isn't in the expected encrypted format.")
        }
        // The MAC is checked first, before anything is decrypted.
        guard sameBytes(mac(key, iv, ciphertext), tag) else {
            throw VWError.failed("A value couldn't be decrypted (wrong key or damaged data).")
        }
        return try key.withEnc { try VWPrim.aesCBC(encrypt: false, key: $0, iv: iv, input: ciphertext) }
    }

    /// Decrypts a wrapped key (an EncString holding 64 bytes). The plain bytes are wiped once they are in the
    /// returned key. nil when the bytes are not a key.
    static func decryptKey(_ text: String, with key: VWKey) throws -> VWKey? {
        var plain = try decrypt(text, with: key)
        defer { plain.wipe() }
        return VWKey(combined: plain)
    }

    /// nil for a missing or empty value.
    static func decryptString(_ text: String?, with key: VWKey) throws -> String? {
        guard let text, !text.isEmpty else { return nil }
        var plain = try decrypt(text, with: key)
        defer { plain.wipe() }   // the temporary bytes; the text made from them is what the item keeps
        guard let s = String(data: plain, encoding: .utf8) else {
            throw VWError.failed("A value isn't valid text.")
        }
        return s
    }

    static func encrypt(_ data: Data, with key: VWKey) throws -> String {
        let iv = VWPrim.random(16)
        let ciphertext = try key.withEnc { try VWPrim.aesCBC(encrypt: true, key: $0, iv: iv, input: data) }
        let tag = mac(key, iv, ciphertext)
        return "2." + iv.base64EncodedString() + "|" + ciphertext.base64EncodedString() + "|" + tag.base64EncodedString()
    }

    static func encrypt(_ text: String, with key: VWKey) throws -> String {
        try encrypt(Data(text.utf8), with: key)
    }

    /// A file as the Bitwarden apps store it: one byte with the type (2), the IV (16 bytes), the MAC (32 bytes), then
    /// the ciphertext. Same cipher and MAC as an EncString of type 2, only in binary.
    static func encryptFile(_ data: Data, with key: VWKey) throws -> Data {
        let iv = VWPrim.random(16)
        let ciphertext = try key.withEnc { try VWPrim.aesCBC(encrypt: true, key: $0, iv: iv, input: data) }
        return Data([2]) + iv + mac(key, iv, ciphertext) + ciphertext
    }

    /// The reverse of `encryptFile`. The MAC is checked before anything is decrypted.
    static func decryptFile(_ bytes: Data, with key: VWKey) throws -> Data {
        let b = Data(bytes)   // starts at index 0
        guard b.count >= 49 + 16 else { throw VWError.failed("The attachment on the server isn't in the expected encrypted format.") }
        guard b[0] == 2 else {
            throw VWError.failed("This attachment uses an encryption type (\(b[0])) that BwLite doesn't support.")
        }
        let iv = b.subdata(in: 1..<17), tag = b.subdata(in: 17..<49), ciphertext = b.subdata(in: 49..<b.count)
        guard sameBytes(mac(key, iv, ciphertext), tag) else {
            throw VWError.failed("The attachment couldn't be decrypted (wrong key or damaged data).")
        }
        return try key.withEnc { try VWPrim.aesCBC(encrypt: false, key: $0, iv: iv, input: ciphertext) }
    }

    /// Decrypts an organization key: EncString type 4 (RSA-OAEP with SHA-1) or 3 (SHA-256).
    static func rsaDecrypt(_ text: String, privateKeyDER: Data) throws -> Data {
        guard let dot = text.firstIndex(of: "."), let type = Int(text[..<dot]),
              let first = text[text.index(after: dot)...].split(separator: "|").first,
              let ciphertext = Data(base64Encoded: String(first)) else {
            throw VWError.failed("An organization key isn't in the expected format.")
        }
        switch type {
        case 4, 6: return try VWPrim.rsaDecrypt(pkcs8: privateKeyDER, ciphertext: ciphertext, sha256: false)
        case 3, 5: return try VWPrim.rsaDecrypt(pkcs8: privateKeyDER, ciphertext: ciphertext, sha256: true)
        default: throw VWError.failed("An organization key uses an encryption type (\(type)) that BwLite doesn't support.")
        }
    }
}
