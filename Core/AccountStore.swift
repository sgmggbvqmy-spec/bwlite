// What stays on disk about the account, and where.

import Foundation

/// What stays on disk about the account. Nothing in it is readable without the master password:
/// the account key and the refresh token are encrypted, and the vault copy is the server's own ciphertext.
nonisolated struct VWAccount: Codable {
    var server: String
    var email: String
    var userId: String
    var kdf: VWKDF
    var protectedKey: String      // the account key, encrypted with the master key (the server's "Key")
    var refreshToken: String?     // encrypted with the account key
    var lastSync: String?
}

nonisolated enum VWStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BwLite", isDirectory: true)
    }
    private static var accountURL: URL { directory.appendingPathComponent("vw-account.json") }
    private static var vaultURL: URL { directory.appendingPathComponent("vw-vault.json") }

    static func loadAccount() -> VWAccount? {
        guard let data = try? Data(contentsOf: accountURL) else { return nil }
        return try? JSONDecoder().decode(VWAccount.self, from: data)
    }

    static func saveAccount(_ account: VWAccount) throws {
        try write(try JSONEncoder().encode(account), to: accountURL)
    }

    static func loadVault() -> Data? { try? Data(contentsOf: vaultURL) }

    static func saveVault(_ data: Data) throws { try write(data, to: vaultURL) }

    /// Removes the account and the local copy of the vault.
    static func wipe() {
        try? FileManager.default.removeItem(at: accountURL)
        try? FileManager.default.removeItem(at: vaultURL)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
