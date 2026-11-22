// Fetching website icons through the Vaultwarden server.

import Foundation
import CryptoKit

/// Website icons come from your own server (`/icons/<host>/icon.png`), which fetches them from the websites.
nonisolated enum VWIcons {
    /// UserDefaults key of the "Show website icons" switch.
    static let showKey = "showWebsiteIcons"

    /// On unless switched off.
    static var enabled: Bool { UserDefaults.standard.object(forKey: showKey) as? Bool ?? true }

    /// What Vaultwarden answers (with status 200) when it has no icon for a site: always the same small picture.
    static let fallbackHash = "01d7ddb3c3c46ca24f7d911abd32849aa19627c8be515273bdfb98100460aacb"

    static func isFallback(_ data: Data) -> Bool {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == fallbackHash
    }

    /// The host name to ask for: the one of an http(s) address (a bare "example.com" counts as https), when it is
    /// a plain domain name (letters, digits, hyphens and dots, with at least one dot). Anything else gets no icon:
    /// IP addresses, other schemes, and anything that could change the address the server is asked for.
    static func host(of address: String) -> String? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text.contains("://") ? text : "https://" + text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), var host = url.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        guard host.count <= 253, host.contains(".") else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        for label in labels {
            guard !label.isEmpty, label.count <= 63, !label.hasPrefix("-"), !label.hasSuffix("-"),
                  label.allSatisfy({ allowed.contains($0) }) else { return nil }
        }
        // 192.168.0.1 and the like have no icon.
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return nil }
        return host
    }
}
