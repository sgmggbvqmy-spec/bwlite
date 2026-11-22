// Touch ID: keeping the vault key in the login keychain.

import Foundation
import Security   // RSA keys and certificates
import LocalAuthentication   // Touch ID

/// Touch ID unlock. With the switch on in Settings and one unlock with the master password, the vault key is
/// kept in the login keychain. Unlocking then asks for your fingerprint first and only after that reads the key
/// back. BwLite does that check itself: a keychain item that demands Touch ID on its own needs an app signed with
/// an Apple Developer ID, and BwLite is signed ad hoc. So this is less safe than typing the master password.
nonisolated enum TouchID {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "BwLite",
         kSecAttrAccount as String: "Vault key for Touch ID",
         kSecUseDataProtectionKeychain as String: false]   // the login keychain
    }

    /// False on a Mac without Touch ID, or while it can't be used right now (lid closed, no finger enrolled).
    static var available: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Shows the Touch ID sheet. False when it was cancelled or didn't match.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""   // no "Enter Password" button: the master password field is right there
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                  localizedReason: reason)) ?? false
    }

    static var hasSavedKey: Bool {
        SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func save(_ key: Data) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = key
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> Data? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
