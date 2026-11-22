// A vault item as the app holds it, decrypted.
//
// Note: new Xcode 26 projects treat every declaration as @MainActor by default.
// The model, crypto and core types (Model/, Crypto/, Core/, Generator/) have nothing to do with the UI,
// so they are explicitly marked nonisolated to allow use from background threads.

import Foundation

/// One vault item, decrypted. The whole vault is decrypted once, right after unlocking, and kept in memory
/// until you lock it. That includes passwords, notes and old passwords, so clicking an item never has to
/// decrypt anything again.
nonisolated struct Entry: Identifiable, Decodable {
    let id: String
    let name: String
    let type: Int          // 1 = login, 2 = secure note, 3 = card, 4 = identity, 5 = SSH key
    let login: Login?
    let folderId: String?  // nil = "No Folder"
    let created: Date?     // dates are parsed once when the list is loaded, so sorting stays fast
    let modified: Date?
    let notes: String?
    let history: [HistoryEntry]   // old passwords, newest first
    /// In the Archive: kept, but hidden from the normal lists.
    var archived = false
    /// The decrypted fields of a card, identity, SSH key, bank account, driver's license or passport, by the name
    /// the server uses for them (see `ItemKind.schema`). Empty for logins and secure notes.
    var data: [String: String] = [:]
    /// The custom fields ("Add Field" in the Bitwarden apps).
    var fields: [CustomField] = []
    /// The files attached to the item. Their contents stay on the server until one is saved.
    var attachments: [ItemAttachment] = []

    nonisolated struct Login: Decodable {
        let username: String?
        let password: String?
        let totp: String?      // the authenticator key: a bare base32 key or an otpauth:// link
        let uris: [URI]?
    }
    nonisolated struct URI: Decodable {
        let uri: String?
        /// How the website is matched: `URIMatch` raw value, nil = the default. Kept as the server has it.
        var match: Int? = nil
    }

    nonisolated struct HistoryEntry: Decodable {
        let date: Date?
        let password: String

        init(date: Date?, password: String) {
            self.date = date
            self.password = password
        }

        private nonisolated enum CodingKeys: String, CodingKey { case lastUsedDate, password }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = VWDate.parse(try c.decodeIfPresent(String.self, forKey: .lastUsedDate))
            password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        }
    }

    init(id: String, name: String, type: Int, login: Login?, folderId: String?, created: Date?,
         modified: Date?, notes: String?, history: [HistoryEntry]) {
        self.id = id
        self.name = name
        self.type = type
        self.login = login
        self.folderId = folderId
        self.created = created
        self.modified = modified
        self.notes = notes
        self.history = history
    }

    private nonisolated enum CodingKeys: String, CodingKey {
        case id, name, type, login, folderId, creationDate, revisionDate, notes, passwordHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(Int.self, forKey: .type)
        login = try c.decodeIfPresent(Login.self, forKey: .login)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        created = VWDate.parse(try c.decodeIfPresent(String.self, forKey: .creationDate))
        modified = VWDate.parse(try c.decodeIfPresent(String.self, forKey: .revisionDate))
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        history = try c.decodeIfPresent([HistoryEntry].self, forKey: .passwordHistory) ?? []
    }

    var user: String? { login?.username }
    /// The item's one-time-code generator, if it has a usable key.
    var totp: Totp? { Totp(login?.totp) }
    var urls: [String] { (login?.uris ?? []).compactMap(\.uri).filter { !$0.isEmpty } }
    /// The host to fetch the website icon of: the first address that has a usable one. Only logins have one.
    var iconHost: String? {
        guard kind == .login else { return nil }
        return urls.lazy.compactMap { VWIcons.host(of: $0) }.first
    }

    /// The websites of a login with their match settings, in the order they are stored.
    var websites: [Website] {
        (login?.uris ?? []).compactMap { u in
            guard let address = u.uri, !address.isEmpty else { return nil }
            return Website(uri: address, match: u.match)
        }
    }
    var kind: ItemKind { ItemKind(rawValue: type) ?? .login }

    /// The grey second line of a list row: the user name (or else the website) of a login, the brand and last
    /// digits of a card, the name of an identity or a license, the fingerprint of an SSH key, and so on.
    var subtitle: String {
        func value(_ key: String) -> String {
            (data[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func joined(_ keys: [String]) -> String {
            keys.map(value).filter { !$0.isEmpty }.joined(separator: " ")
        }
        switch kind {
        case .login:
            if let u = user, !u.isEmpty { return u }
            return sortURL ?? ""
        case .card:
            var parts = [value("brand")].filter { !$0.isEmpty }
            let digits = value("number").filter(\.isNumber)
            if digits.count >= 4 { parts.append("\u{2022}\u{2022}\u{2022}\u{2022} " + String(digits.suffix(4))) }
            return parts.joined(separator: ", ")
        case .identity:
            let name = joined(["firstName", "middleName", "lastName"])
            return name.isEmpty ? value("email") : name
        case .sshKey:
            return value("keyFingerprint")
        case .bankAccount:
            return value("bankName")
        case .driversLicense:
            return joined(["firstName", "middleName", "lastName"])
        case .passport:
            return joined(["givenName", "surname"])
        case .secureNote:
            return ""
        }
    }

    /// Host name of the first URL without "www.", used when sorting by website.
    var sortURL: String? {
        guard let first = urls.first else { return nil }
        var host = URL(string: first)?.host ?? first
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.lowercased()
    }
}
