// A website of a login and how it is matched (the URI match setting).

import Foundation

/// How a website of a login is matched against the address of a page ("URI match detection" in the
/// Bitwarden apps). The raw values are the numbers the server stores.
nonisolated enum URIMatch: Int, CaseIterable, Identifiable {
    case domain = 0, host = 1, startsWith = 2, exact = 3, regex = 4, never = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .domain:     return "Base Domain"
        case .host:       return "Host"
        case .startsWith: return "Starts With"
        case .exact:      return "Exact"
        case .regex:      return "Regular Expression"
        case .never:      return "Never"
        }
    }

    /// One line that says what the setting does.
    var summary: String {
        switch self {
        case .domain:     return "example.com matches www.example.com and any other subdomain."
        case .host:       return "Matches the host name and the port only."
        case .startsWith: return "Matches addresses that begin with this text."
        case .exact:      return "Matches this exact address only."
        case .regex:      return "Matches addresses that fit this regular expression (advanced)."
        case .never:      return "This website is never offered for autofill."
        }
    }

    /// The name shown for a stored value: nil is the default (base domain, as in the Bitwarden apps).
    static func title(for stored: Int?) -> String {
        guard let stored else { return "Default" }
        return URIMatch(rawValue: stored)?.title ?? "Other (\(stored))"
    }
}

/// One website of a login: the address and how it is matched. A string literal is a website with the default match.
nonisolated struct Website: Equatable, ExpressibleByStringLiteral {
    var uri: String
    /// A `URIMatch` raw value; nil = default. Values this version doesn't know are passed through untouched.
    var match: Int?

    init(uri: String, match: Int? = nil) {
        self.uri = uri
        self.match = match
    }

    init(stringLiteral value: String) { self.init(uri: value) }
}
