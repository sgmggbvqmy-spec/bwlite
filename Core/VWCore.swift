// Native Vaultwarden core.
//
// BwLite talks to your Vaultwarden server itself: the same HTTP calls the Bitwarden apps make (prelogin,
// connect/token, sync, ciphers), and the same encryption (PBKDF2 or Argon2id, AES-256-CBC + HMAC-SHA256).
// Nothing is run outside this app. The server only ever sees encrypted data.

import Foundation

nonisolated struct VWStatus {
    var hasAccount: Bool
    var server: String
    var email: String?
    var lastSync: Date?
}

nonisolated struct VWSnapshot {
    var entries: [Entry]
    /// Items in the trash.
    var deleted: [Entry]
    /// Items in the Archive.
    var archived: [Entry]
    var folders: [Folder]
    /// Items that couldn't be decrypted (an organization key that is missing, for example).
    var skipped: Int
    var lastSync: Date?
}

/// Does all the talking to the server and all the decrypting. The account key and the tokens live here,
/// in memory only, from unlocking until locking.
actor VWCore {
    private static let clientVersion = "2026.10.2"

    private var account: VWAccount?
    private var server = ""
    private var userKey: VWKey?
    private var orgKeys: [String: VWKey] = [:]
    private var accessToken: String?
    private var refreshToken: String?
    /// The last sync answer from the server, as it came (encrypted).
    private var raw: [String: Any] = [:]

    // MARK: State

    func status() -> VWStatus {
        let stored = VWStore.loadAccount()
        let shown = stored?.server ?? VW.savedServer
        return VWStatus(hasAccount: stored != nil, server: shown, email: stored?.email,
                        lastSync: VWDate.parse(stored?.lastSync))
    }

    /// Remembers the server for the next login. Returns an error message, or nil.
    func setServer(_ text: String) -> String? {
        let url = VW.normalizedServer(text)
        if url.isEmpty {
            UserDefaults.standard.removeObject(forKey: VW.serverKey)
            return nil
        }
        if let problem = VW.serverProblem(url) { return problem }
        UserDefaults.standard.set(url, forKey: VW.serverKey)
        return nil
    }

    /// Forgets the keys and the tokens. The account and the local copy of the vault stay on disk.
    /// The keys are overwritten with zeros; the tokens, being text, can only be let go (see README, "Memory").
    func lock() {
        userKey?.wipe()
        for key in orgKeys.values { key.wipe() }
        userKey = nil
        orgKeys = [:]
        accessToken = nil
        refreshToken = nil
        raw = [:]
    }

    /// Removes the account and the local copy of the vault from this Mac.
    func logout() {
        lock()
        account = nil
        VWStore.wipe()
    }

    // MARK: Logging in and unlocking

    /// Logs in with the master password (and a two-step code if the account has one), loads the vault and
    /// keeps it, encrypted, on this Mac for offline use.
    func login(email: String, password: String, code: String) async throws -> VWSnapshot {
        let url = VW.normalizedServer(VW.savedServer)
        guard !url.isEmpty else { throw VWError.failed("Set your server in Settings (⌘,) first.") }
        if let problem = VW.serverProblem(url) { throw VWError.failed(problem) }
        lock()
        server = url
        let address = VWCrypto.normalizedEmail(email)
        do {
            let kdf = try await prelogin(address)
            var masterKey = try VWCrypto.masterKey(password: password, email: address, kdf: kdf)
            defer { masterKey.wipe() }
            var form: [String: String] = [
                "grant_type": "password",
                "username": address,
                "password": try VWCrypto.masterHash(masterKey: masterKey, password: password),
                "scope": "api offline_access",
                "client_id": "desktop",
                "deviceType": "7",
                "deviceIdentifier": VW.deviceId,
                "deviceName": "BwLite",
            ]
            let twoStep = code.trimmingCharacters(in: .whitespaces)
            if !twoStep.isEmpty {
                form["twoFactorProvider"] = "0"   // 0 = authenticator app
                form["twoFactorToken"] = twoStep
                form["twoFactorRemember"] = "0"
            }
            let tokenData: Data
            do {
                tokenData = try await perform("POST", "/identity/connect/token", form: form, token: nil)
            } catch let e as VWHTTPError where e.status == 400 {
                if let providers = e.json?["TwoFactorProviders"] as? [Any] {
                    let ids = providers.map { "\($0)" }
                    if ids.contains("0") {
                        throw VWError.failed("This account asks for a two-step code. Enter the code from your authenticator app.")
                    }
                    throw VWError.failed("This account's two-step login (method \(ids.joined(separator: ", "))) isn't supported. BwLite supports authenticator apps.")
                }
                throw e
            }
            guard let token = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
                  let access = token["access_token"] as? String else {
                throw VWError.failed("The server's login answer isn't what Vaultwarden sends. Is the server address right?")
            }
            guard let protectedKey = token["Key"] as? String, !protectedKey.isEmpty else {
                throw VWError.failed("This account has no master-password key (single sign-on or key connector). BwLite can't open it.")
            }
            let key = try Self.accountKey(protectedKey, masterKey: masterKey)
            accessToken = access
            refreshToken = token["refresh_token"] as? String
            userKey = key

            let syncData = try await perform("GET", "/api/sync?excludeDomains=true", token: access)
            guard let sync = try JSONSerialization.jsonObject(with: syncData) as? [String: Any],
                  let profile = sync["profile"] as? [String: Any], let userId = profile["id"] as? String else {
                throw VWError.failed("The server's vault answer isn't what Vaultwarden sends.")
            }
            var stored = VWAccount(server: url, email: address, userId: userId, kdf: kdf, protectedKey: protectedKey,
                                   refreshToken: nil, lastSync: Self.now())
            if let refresh = refreshToken { stored.refreshToken = try VWCrypto.encrypt(refresh, with: key) }
            try VWStore.saveAccount(stored)
            try VWStore.saveVault(syncData)
            account = stored
            raw = sync
            return try snapshot()
        } catch {
            lock()
            throw error
        }
    }

    /// Unlocks with the master password. Works offline: only the local copy of the vault is read.
    func unlock(password: String) async throws -> VWSnapshot {
        guard let stored = VWStore.loadAccount() else {
            throw VWError.failed("No account is set up on this Mac yet. Log in first.")
        }
        var masterKey = try VWCrypto.masterKey(password: password, email: stored.email, kdf: stored.kdf)
        defer { masterKey.wipe() }
        let key: VWKey
        do { key = try Self.accountKey(stored.protectedKey, masterKey: masterKey) }
        catch { throw VWError.failed("Wrong master password.") }
        return try open(stored, with: key)
    }

    /// Unlocks with the vault key itself, which Touch ID hands back after a fingerprint (see `TouchID`).
    func unlock(userKey data: Data) async throws -> VWSnapshot {
        guard let stored = VWStore.loadAccount() else {
            throw VWError.failed("No account is set up on this Mac yet. Log in first.")
        }
        guard let key = VWKey(combined: data) else {
            throw VWError.failed("The key saved for Touch ID is not valid.")
        }
        let snap = try open(stored, with: key)
        // A key that doesn't belong to this vault decrypts none of its logins.
        if snap.entries.isEmpty && snap.deleted.isEmpty && snap.archived.isEmpty && snap.skipped > 0 {
            lock()
            throw VWError.failed("The key saved for Touch ID doesn't match this vault.")
        }
        return snap
    }

    /// The vault key while unlocked, for `TouchID` to keep; nil while locked.
    func userKeyData() -> Data? { userKey?.combined }

    private func open(_ stored: VWAccount, with key: VWKey) throws -> VWSnapshot {
        guard let data = VWStore.loadVault(),
              let sync = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw VWError.failed("The local copy of the vault is missing. Log out and log in again.")
        }
        lock()
        account = stored
        server = stored.server
        userKey = key
        raw = sync
        if let encrypted = stored.refreshToken { refreshToken = try? VWCrypto.decryptString(encrypted, with: key) }
        return try snapshot()
    }

    private static func accountKey(_ protectedKey: String, masterKey: Data) throws -> VWKey {
        guard let key = try VWCrypto.decryptKey(protectedKey, with: VWCrypto.stretch(masterKey)) else {
            throw VWError.failed("The account key has an unexpected size.")
        }
        return key
    }

    // MARK: Reading

    /// Downloads the vault again (needs the network) and keeps the new copy.
    func sync() async throws -> VWSnapshot {
        guard userKey != nil else { throw VWError.failed("The vault is locked.") }
        let data = try await request("GET", "/api/sync?excludeDomains=true")
        guard let sync = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VWError.failed("The server's vault answer isn't what Vaultwarden sends.")
        }
        raw = sync
        try VWStore.saveVault(data)
        if var stored = account {
            stored.lastSync = Self.now()
            try VWStore.saveAccount(stored)
            account = stored
        }
        return try snapshot()
    }

    /// Decrypts the last downloaded vault: the items, the ones in the Archive and in the trash, and the folders.
    func snapshot() throws -> VWSnapshot {
        guard let userKey else { throw VWError.failed("The vault is locked.") }
        orgKeys = organizationKeys(userKey)
        var entries: [Entry] = []
        var deleted: [Entry] = []
        var archived: [Entry] = []
        var skipped = 0
        for cipher in (raw["ciphers"] as? [[String: Any]]) ?? [] {
            guard let type = cipher["type"] as? Int, ItemKind(rawValue: type) != nil else { continue }
            let inTrash = (cipher["deletedDate"] as? String) != nil
            do {
                if let entry = try decryptedEntry(from: cipher) {
                    if inTrash { deleted.append(entry) } else if entry.archived { archived.append(entry) } else { entries.append(entry) }
                }
            } catch {
                skipped += 1
            }
        }
        var folders: [Folder] = []
        for folder in (raw["folders"] as? [[String: Any]]) ?? [] {
            guard let id = folder["id"] as? String,
                  let name = (try? VWCrypto.decryptString(folder["name"] as? String, with: userKey)) ?? nil else { continue }
            folders.append(Folder(id: id, name: name))
        }
        return VWSnapshot(entries: entries, deleted: deleted, archived: archived, folders: folders, skipped: skipped,
                          lastSync: VWDate.parse(account?.lastSync))
    }

    /// The keys of the organizations you belong to: each is encrypted with the account's RSA key.
    private func organizationKeys(_ userKey: VWKey) -> [String: VWKey] {
        guard let profile = raw["profile"] as? [String: Any],
              let encryptedPrivate = profile["privateKey"] as? String,
              var der = try? VWCrypto.decrypt(encryptedPrivate, with: userKey) else { return [:] }
        defer { der.wipe() }
        var keys: [String: VWKey] = [:]
        for org in (profile["organizations"] as? [[String: Any]]) ?? [] {
            guard let id = org["id"] as? String, let encrypted = org["key"] as? String,
                  var plain = try? VWCrypto.rsaDecrypt(encrypted, privateKeyDER: der) else { continue }
            defer { plain.wipe() }
            guard let key = VWKey(combined: plain) else { continue }
            keys[id] = key
        }
        return keys
    }

    /// The key that encrypts one item's fields: the item's own key if it has one, otherwise the key of its
    /// organization or the account key.
    private func fieldKey(for cipher: [String: Any]) throws -> VWKey {
        guard let userKey else { throw VWError.failed("The vault is locked.") }
        var key = userKey
        if let org = cipher["organizationId"] as? String {
            guard let orgKey = orgKeys[org] else { throw VWError.failed("An organization key is missing.") }
            key = orgKey
        }
        if let own = cipher["key"] as? String, !own.isEmpty {
            guard let itemKey = try VWCrypto.decryptKey(own, with: key) else {
                throw VWError.failed("An item key has an unexpected size.")
            }
            return itemKey
        }
        return key
    }

    private func decryptedEntry(from cipher: [String: Any]) throws -> Entry? {
        guard let id = cipher["id"] as? String else { return nil }
        let key = try fieldKey(for: cipher)
        func text(_ value: Any?) throws -> String? { try VWCrypto.decryptString(value as? String, with: key) }

        let login = cipher["login"] as? [String: Any] ?? [:]
        var uris: [Entry.URI] = []
        for u in (login["uris"] as? [[String: Any]]) ?? [] { uris.append(Entry.URI(uri: try text(u["uri"]), match: u["match"] as? Int)) }
        var history: [Entry.HistoryEntry] = []
        for h in (cipher["passwordHistory"] as? [[String: Any]]) ?? [] {
            guard let password = try text(h["password"]) else { continue }
            history.append(Entry.HistoryEntry(date: VWDate.parse(h["lastUsedDate"] as? String), password: password))
        }
        let name = try text(cipher["name"]) ?? ""
        let notes = try text(cipher["notes"])
        let type = (cipher["type"] as? Int) ?? 1
        var entryLogin: Entry.Login?
        if type == 1 {
            entryLogin = Entry.Login(username: try text(login["username"]), password: try text(login["password"]),
                                     totp: try text(login["totp"]), uris: uris)
        }
        var entry = Entry(id: id, name: name, type: type, login: entryLogin,
                          folderId: cipher["folderId"] as? String,
                          created: VWDate.parse(cipher["creationDate"] as? String),
                          modified: VWDate.parse(cipher["revisionDate"] as? String),
                          notes: notes, history: history)
        entry.archived = (cipher["archivedDate"] as? String) != nil
        if let kind = ItemKind(rawValue: type), !kind.schema.isEmpty, let section = cipher[kind.jsonKey] as? [String: Any] {
            for spec in kind.schema {
                if let v = try text(section[spec.key]), !v.isEmpty { entry.data[spec.key] = v }
            }
        }
        for f in (cipher["fields"] as? [[String: Any]]) ?? [] {
            entry.fields.append(CustomField(name: try text(f["name"]) ?? "", value: try text(f["value"]) ?? "",
                                            kind: CustomField.Kind(rawValue: (f["type"] as? Int) ?? 0) ?? .text,
                                            linkedId: f["linkedId"] as? Int))
        }
        for a in (cipher["attachments"] as? [[String: Any]]) ?? [] {
            guard let attachmentId = a["id"] as? String else { continue }
            // The server sends the size as text. A name that can't be read must not hide the whole item.
            let size = (a["size"] as? String).flatMap { Int64($0) } ?? (a["size"] as? Int).map { Int64($0) } ?? 0
            let name = (try? text(a["fileName"])) ?? ""
            entry.attachments.append(ItemAttachment(id: attachmentId, fileName: name.isEmpty ? "Attachment" : name, size: size))
        }
        return entry
    }

    // MARK: Changing

    /// Empty text becomes JSON null, which is how Bitwarden stores "no value".
    private func sealed(_ text: String?, _ key: VWKey) throws -> Any {
        guard let text, !text.isEmpty else { return NSNull() }
        return try VWCrypto.encrypt(text, with: key)
    }

    /// The custom fields as the server stores them: names and values encrypted. Empty ones are left out.
    private func encryptedFields(_ list: [CustomField], _ key: VWKey) throws -> [[String: Any]] {
        try list.compactMap { f -> [String: Any]? in
            let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty && f.value.isEmpty && f.kind != .linked { return nil }
            let value: Any = try (f.kind == .linked ? NSNull() as Any : sealed(f.value, key))
            return ["type": f.kind.rawValue,
                    "name": try sealed(name, key),
                    "value": value,
                    "linkedId": f.linkedId.map { $0 as Any } ?? NSNull()]
        }
    }

    private func orNull(_ text: String?) -> Any {
        guard let text, !text.isEmpty else { return NSNull() }
        return text
    }

    /// Creates a login item on the server (needs the network) and returns its id.
    func createLogin(name: String, username: String, password: String, websites: [Website],
                     notes: String, folderId: String?, totp: String = "",
                     fields: [CustomField] = []) async throws -> String {
        guard let userKey, let account else { throw VWError.failed("The vault is locked.") }
        let login: [String: Any] = [
            "username": try sealed(username, userKey),
            "password": try sealed(password, userKey),
            "totp": try sealed(totp, userKey),
            "uris": try encryptedURIs(websites, key: userKey, existing: []),
        ]
        let body: [String: Any] = [
            "organizationId": NSNull(),
            "folderId": orNull(folderId),
            "type": 1,
            "name": try VWCrypto.encrypt(name, with: userKey),
            "notes": try sealed(notes, userKey),
            "favorite": false,
            "fields": try encryptedFields(fields, userKey),
            "login": login,
            "reprompt": 0,
            "key": NSNull(),
            "encryptedFor": account.userId,
        ]
        let data = try await request("POST", "/api/ciphers", json: body)
        let created = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return created?["id"] as? String ?? ""
    }

    /// The websites as the server stores them: addresses encrypted, match setting as a number (null = default).
    /// A website whose address is unchanged keeps everything else it had (its checksum, for example), so editing
    /// a login never loses what BwLite doesn't show. The match setting always comes from `websites`.
    private func encryptedURIs(_ websites: [Website], key: VWKey, existing: [[String: Any]]) throws -> [[String: Any]] {
        var old: [(address: String?, json: [String: Any])] = []
        for u in existing { old.append((try VWCrypto.decryptString(u["uri"] as? String, with: key), u)) }
        var result: [[String: Any]] = []
        for w in websites {
            var item: [String: Any]
            if let i = old.firstIndex(where: { $0.address == w.uri }) {
                item = old.remove(at: i).json
            } else {
                item = ["uri": try VWCrypto.encrypt(w.uri, with: key)]
            }
            item["match"] = w.match ?? NSNull()
            result.append(item)
        }
        return result
    }

    private func rawCipher(_ id: String) throws -> [String: Any] {
        for c in (raw["ciphers"] as? [[String: Any]]) ?? [] where (c["id"] as? String) == id { return c }
        throw VWError.failed("This item isn't in the local copy of the vault. Sync first.")
    }

    /// The fields a cipher update sends. The server replaces the whole item with them, so everything that
    /// isn't being changed (custom fields, security settings, ...) is sent back exactly as it came.
    private func updateBody(from cipher: [String: Any], userId: String) -> [String: Any] {
        var body: [String: Any] = [:]
        for k in ["folderId", "organizationId", "key", "type", "name", "notes", "fields", "login", "secureNote", "card",
                  "identity", "sshKey", "bankAccount", "driversLicense", "passport", "favorite", "reprompt",
                  "passwordHistory", "archivedDate"] {
            body[k] = cipher[k] ?? NSNull()
        }
        body["encryptedFor"] = userId
        body["lastKnownRevisionDate"] = cipher["revisionDate"] ?? NSNull()
        return body
    }

    /// Changes name, user name, password, websites, notes and authenticator key of an existing login
    /// (needs the network). An old password goes into the item's password history.
    func updateLogin(id: String, name: String, username: String, password: String, websites: [Website],
                     notes: String, totp: String, fields: [CustomField]? = nil) async throws {
        guard let account else { throw VWError.failed("The vault is locked.") }
        let cipher = try rawCipher(id)
        let key = try fieldKey(for: cipher)
        var body = updateBody(from: cipher, userId: account.userId)
        var login = cipher["login"] as? [String: Any] ?? [:]

        let oldPassword = try VWCrypto.decryptString(login["password"] as? String, with: key)
        login["uris"] = try encryptedURIs(websites, key: key, existing: (login["uris"] as? [[String: Any]]) ?? [])
        login["username"] = try sealed(username, key)
        login["password"] = try sealed(password, key)
        login["totp"] = try sealed(totp, key)

        if let old = oldPassword, !old.isEmpty, old != password {
            var history = cipher["passwordHistory"] as? [[String: Any]] ?? []
            let used = (login["passwordRevisionDate"] as? String) ?? (cipher["revisionDate"] as? String) ?? Self.now()
            history.insert(["password": try VWCrypto.encrypt(old, with: key), "lastUsedDate": used], at: 0)
            body["passwordHistory"] = Array(history.prefix(5))
            login["passwordRevisionDate"] = Self.now()
        }
        body["login"] = login
        body["name"] = try VWCrypto.encrypt(name, with: key)
        body["notes"] = try sealed(notes, key)
        if let fields { body["fields"] = try encryptedFields(fields, key) }   // nil: leave them as they are
        _ = try await request("PUT", "/api/ciphers/\(id)", json: body)
    }

    /// Creates a secure note, card, identity, SSH key, bank account, driver's license or passport
    /// (needs the network) and returns its id. `data` holds the fields by their `ItemKind.schema` keys.
    func createItem(kind: ItemKind, name: String, notes: String, folderId: String?,
                    data: [String: String], fields: [CustomField]) async throws -> String {
        guard kind != .login else { throw VWError.failed("A login is made with createLogin.") }
        guard let userKey, let account else { throw VWError.failed("The vault is locked.") }
        if let label = kind.missingField(in: data) { throw VWError.failed("\(label) is needed for \(kind.title).") }
        var section: [String: Any] = [:]
        if kind == .secureNote {
            section["type"] = 0
        } else {
            for spec in kind.schema { section[spec.key] = try sealed(data[spec.key], userKey) }
        }
        let body: [String: Any] = [
            "organizationId": NSNull(),
            "folderId": orNull(folderId),
            "type": kind.rawValue,
            "name": try VWCrypto.encrypt(name, with: userKey),
            "notes": try sealed(notes, userKey),
            "favorite": false,
            "fields": try encryptedFields(fields, userKey),
            kind.jsonKey: section,
            "reprompt": 0,
            "key": NSNull(),
            "encryptedFor": account.userId,
        ]
        let response = try await request("POST", "/api/ciphers", json: body)
        let created = (try? JSONSerialization.jsonObject(with: response)) as? [String: Any]
        return created?["id"] as? String ?? ""
    }

    /// Changes name, notes, fields and custom fields of an item that is not a login (needs the network).
    /// Anything in the item that BwLite doesn't know about is sent back as it came.
    func updateItem(id: String, name: String, notes: String, data: [String: String],
                    fields: [CustomField]) async throws {
        guard let account else { throw VWError.failed("The vault is locked.") }
        let cipher = try rawCipher(id)
        guard let type = cipher["type"] as? Int, let kind = ItemKind(rawValue: type), kind != .login else {
            throw VWError.failed("This item is a login.")
        }
        if let label = kind.missingField(in: data) { throw VWError.failed("\(label) is needed for \(kind.title).") }
        let key = try fieldKey(for: cipher)
        var body = updateBody(from: cipher, userId: account.userId)
        if !kind.schema.isEmpty {
            var section = cipher[kind.jsonKey] as? [String: Any] ?? [:]
            for spec in kind.schema { section[spec.key] = try sealed(data[spec.key], key) }
            body[kind.jsonKey] = section
        }
        body["name"] = try VWCrypto.encrypt(name, with: key)
        body["notes"] = try sealed(notes, key)
        body["fields"] = try encryptedFields(fields, key)
        _ = try await request("PUT", "/api/ciphers/\(id)", json: body)
    }

    /// Puts an item into another folder (nil = no folder). Needs the network.
    /// Takes an item out of the trash.
    func restoreItem(id: String) async throws {
        _ = try await request("PUT", "/api/ciphers/\(id)/restore")
    }

    /// Deletes an item for good. It can't be restored.
    func deleteItemForever(id: String) async throws {
        _ = try await request("DELETE", "/api/ciphers/\(id)")
    }

    /// Makes a folder and returns its id. The name is encrypted here, the server never sees it.
    func createFolder(name: String) async throws -> String {
        guard let userKey else { throw VWError.failed("The vault is locked.") }
        let data = try await request("POST", "/api/folders", json: ["name": try VWCrypto.encrypt(name, with: userKey)])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw VWError.failed("The server's answer to the new folder isn't what Vaultwarden sends.")
        }
        return id
    }

    /// Gives a folder a new name (encrypted here, like when it was made).
    func renameFolder(id: String, name: String) async throws {
        guard let userKey else { throw VWError.failed("The vault is locked.") }
        _ = try await request("PUT", "/api/folders/\(id)", json: ["name": try VWCrypto.encrypt(name, with: userKey)])
    }

    /// Removes a folder. Its items are kept and have no folder afterwards.
    func deleteFolder(id: String) async throws {
        _ = try await request("DELETE", "/api/folders/\(id)")
    }

    func moveItem(id: String, folderId: String?) async throws {
        let cipher = try rawCipher(id)
        let body: [String: Any] = ["folderId": orNull(folderId), "favorite": (cipher["favorite"] as? Bool) ?? false]
        _ = try await request("PUT", "/api/ciphers/\(id)/partial", json: body)
    }

    /// Moves an item to the trash on the server (needs the network). It can be restored from there.
    func deleteItem(id: String) async throws {
        _ = try await request("PUT", "/api/ciphers/\(id)/delete")
    }

    /// Puts an item into the Archive: kept, but out of the normal lists.
    func archiveItem(id: String) async throws {
        _ = try await request("PUT", "/api/ciphers/\(id)/archive")
    }

    /// Takes an item out of the Archive.
    func unarchiveItem(id: String) async throws {
        _ = try await request("PUT", "/api/ciphers/\(id)/unarchive")
    }

    // MARK: Attachments

    /// Downloads an attachment and decrypts it (needs the network). The server is asked again for the attachment
    /// each time, because the download link in the synced copy only works for a few minutes.
    func downloadAttachment(itemId: String, attachmentId: String) async throws -> (name: String, data: Data) {
        let cipher = try rawCipher(itemId)
        let key = try fieldKey(for: cipher)
        let answer = try await request("GET", "/api/ciphers/\(itemId)/attachment/\(attachmentId)")
        guard let meta = try JSONSerialization.jsonObject(with: answer) as? [String: Any],
              let link = meta["url"] as? String else {
            throw VWError.failed("The server's answer about the attachment isn't what Vaultwarden sends.")
        }
        // Vaultwarden keeps the files itself, at /attachments/<item>/<file>?token=... . The address in the link
        // is the server's own idea of its name, so only the part from there on is used, with the address BwLite
        // was given (and its certificate settings).
        guard let marker = link.range(of: "/attachments/") else {
            throw VWError.failed("This server keeps attachments outside Vaultwarden (the link points elsewhere), which BwLite can't download yet.")
        }
        let encrypted = try await request("GET", String(link[marker.lowerBound...]))
        // A file has its own key, wrapped with the item's key. Old attachments have none: the item's key is used.
        var fileKey = key
        if let wrapped = meta["key"] as? String, !wrapped.isEmpty {
            guard let own = try VWCrypto.decryptKey(wrapped, with: key) else {
                throw VWError.failed("An attachment key has an unexpected size.")
            }
            fileKey = own
        }
        let name = try? VWCrypto.decryptString(meta["fileName"] as? String, with: key)
        return (name ?? "attachment", try VWCrypto.decryptFile(encrypted, with: fileKey))
    }

    /// Encrypts a file and attaches it to an item (needs the network). If sending the contents fails, the empty
    /// attachment the server made for it is removed again.
    func uploadAttachment(itemId: String, fileName: String, data: Data) async throws {
        let cipher = try rawCipher(itemId)
        let key = try fieldKey(for: cipher)
        let fileKey = VWKey(enc: VWPrim.random(32), mac: VWPrim.random(32))
        let encrypted = try VWCrypto.encryptFile(data, with: fileKey)
        let encryptedName = try VWCrypto.encrypt(fileName, with: key)
        var fileKeyBytes = fileKey.combined
        defer { fileKeyBytes.wipe() }
        let created = try await request("POST", "/api/ciphers/\(itemId)/attachment/v2", json: [
            "fileName": encryptedName,
            "key": try VWCrypto.encrypt(fileKeyBytes, with: key),
            "fileSize": encrypted.count,
        ])
        guard let answer = try JSONSerialization.jsonObject(with: created) as? [String: Any],
              let attachmentId = answer["attachmentId"] as? String else {
            throw VWError.failed("The server's answer to the new attachment isn't what Vaultwarden sends.")
        }
        let boundary = "BwLite" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"data\"; filename=\"\(encryptedName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body.append(encrypted)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        do {
            _ = try await request("POST", "/api/ciphers/\(itemId)/attachment/\(attachmentId)",
                                  raw: (body, "multipart/form-data; boundary=\(boundary)"))
        } catch {
            _ = try? await request("DELETE", "/api/ciphers/\(itemId)/attachment/\(attachmentId)")
            throw error
        }
    }

    /// Removes an attachment from an item for good (needs the network).
    func deleteAttachment(itemId: String, attachmentId: String) async throws {
        _ = try await request("DELETE", "/api/ciphers/\(itemId)/attachment/\(attachmentId)")
    }

    /// Removes and attaches what was chosen in the edit screen (needs the network). Removals go first. Every one
    /// that is done is reported, and the first failure stops the rest, so the caller keeps what is left and can
    /// try again without sending a file twice. An attachment that is gone already (removed in another app) counts
    /// as removed.
    func changeAttachments(itemId: String, remove: [String], add: [(token: UUID, url: URL)]) async -> AttachmentChanges {
        var result = AttachmentChanges()
        let listed = ((try? rawCipher(itemId))?["attachments"] as? [[String: Any]]) ?? []
        let known = Set(listed.compactMap { $0["id"] as? String })
        for id in remove {
            if known.contains(id) {
                do {
                    try await deleteAttachment(itemId: itemId, attachmentId: id)
                } catch {
                    result.failure = "An attachment couldn't be removed: \(error.localizedDescription)"
                    return result
                }
            }
            result.removed.append(id)
        }
        for file in add {
            let name = file.url.lastPathComponent
            do {
                let data = try Data(contentsOf: file.url)
                try await uploadAttachment(itemId: itemId, fileName: name, data: data)
                result.added.append(file.token)
            } catch {
                result.failure = "\(name) couldn't be attached: \(error.localizedDescription)"
                return result
            }
        }
        return result
    }

    // MARK: Website icons

    /// The icon of a website as the server has it, or nil when there is none (or icons are switched off, or the
    /// vault is locked). Sent to the server: only the host name, with no login token. Redirects are not followed, so
    /// a server set up to pass icons on to another service gets no icons here rather than a request to that service.
    func icon(forHost host: String) async -> Data? {
        guard VWIcons.enabled, userKey != nil, VWIcons.host(of: host) == host else { return nil }
        guard let data = try? await perform("GET", "/icons/\(host)/icon.png", token: nil, followRedirects: false),
              !data.isEmpty, !VWIcons.isFallback(data) else { return nil }
        return data
    }

    // MARK: Account

    // Every one of these asks the server to check the current master password, and every one ends the login of
    // this Mac: the server gives the account a new security stamp (which also ends the login of every other
    // device) and the tokens held here stop working. The caller logs out here afterwards and asks for a new login.

    /// Checks `password` against this Mac's copy of the account (nothing is sent) and returns the master key.
    /// The caller wipes it.
    private func confirmedMasterKey(_ password: String) throws -> Data {
        guard let account, userKey != nil else { throw VWError.failed("The vault is locked.") }
        var masterKey = try VWCrypto.masterKey(password: password, email: account.email, kdf: account.kdf)
        do { _ = try Self.accountKey(account.protectedKey, masterKey: masterKey) }
        catch {
            masterKey.wipe()
            throw VWError.failed("Wrong master password.")
        }
        return masterKey
    }

    /// The account key encrypted with the key stretched from `masterKey`: what the server keeps as "Key".
    private func wrappedAccountKey(masterKey: Data) throws -> String {
        guard let userKey else { throw VWError.failed("The vault is locked.") }
        var plain = userKey.combined
        defer { plain.wipe() }
        return try VWCrypto.encrypt(plain, with: VWCrypto.stretch(masterKey))
    }

    /// The new login data for the server: the new master password hash and the account key wrapped for it. The
    /// vault itself is not touched, because the account key stays the same.
    private func newLogin(password: String, email: String, kdf: VWKDF) throws -> [String: Any] {
        var masterKey = try VWCrypto.masterKey(password: password, email: email, kdf: kdf)
        defer { masterKey.wipe() }
        return ["salt": email, "kdf": kdf.json,
                "hash": try VWCrypto.masterHash(masterKey: masterKey, password: password),
                "wrapped": try wrappedAccountKey(masterKey: masterKey)]
    }

    /// The `authenticationData` and `unlockData` the server wants (same salt and KDF settings in both).
    private func loginChange(_ login: [String: Any]) -> [String: Any] {
        ["authenticationData": ["salt": login["salt"] as Any, "kdf": login["kdf"] as Any,
                                "masterPasswordAuthenticationHash": login["hash"] as Any],
         "unlockData": ["salt": login["salt"] as Any, "kdf": login["kdf"] as Any,
                        "masterKeyWrappedUserKey": login["wrapped"] as Any]]
    }

    /// Changes the master password. `hint` replaces the password hint (empty: none).
    func changePassword(current: String, new: String, hint: String) async throws {
        guard let account else { throw VWError.failed("The vault is locked.") }
        guard !new.isEmpty else { throw VWError.failed("Enter a new master password.") }
        var oldKey = try confirmedMasterKey(current)
        defer { oldKey.wipe() }
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = loginChange(try newLogin(password: new, email: account.email, kdf: account.kdf))
        body["masterPasswordHash"] = try VWCrypto.masterHash(masterKey: oldKey, password: current)
        body["masterPasswordHint"] = trimmedHint.isEmpty ? NSNull() : trimmedHint
        _ = try await request("POST", "/api/accounts/password", json: body)
    }

    /// The address as the server should keep it: the master key is derived with the email as salt, so it must be
    /// exactly what is used to log in later (trimmed, lower case).
    private func validNewEmail(_ text: String) throws -> String {
        let address = VWCrypto.normalizedEmail(text)
        guard let at = address.firstIndex(of: "@"), at != address.startIndex, address.index(after: at) != address.endIndex,
              !address.contains(where: \.isWhitespace) else {
            throw VWError.failed("That isn't a valid email address.")
        }
        guard address != account?.email else { throw VWError.failed("That is already the email of this account.") }
        return address
    }

    /// First step of changing the email: the server sends a code to the new address.
    func requestEmailChange(password: String, newEmail: String) async throws {
        let address = try validNewEmail(newEmail)
        var oldKey = try confirmedMasterKey(password)
        defer { oldKey.wipe() }
        let body: [String: Any] = ["masterPasswordHash": try VWCrypto.masterHash(masterKey: oldKey, password: password),
                                   "newEmail": address]
        _ = try await request("POST", "/api/accounts/email-token", json: body)
    }

    /// Second step: changes the email with the code from the first step. The master password stays the same,
    /// but the master key is derived with the new email as salt, so the account key is wrapped again.
    func changeEmail(password: String, newEmail: String, code: String) async throws {
        guard let account else { throw VWError.failed("The vault is locked.") }
        let address = try validNewEmail(newEmail)
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw VWError.failed("Enter the code that was sent to the new address.") }
        var oldKey = try confirmedMasterKey(password)
        defer { oldKey.wipe() }
        let login = try newLogin(password: password, email: address, kdf: account.kdf)
        let body: [String: Any] = ["masterPasswordHash": try VWCrypto.masterHash(masterKey: oldKey, password: password),
                                   "newEmail": address, "key": login["wrapped"] as Any,
                                   "newMasterPasswordHash": login["hash"] as Any, "token": token]
        _ = try await request("POST", "/api/accounts/email", json: body)
    }

    /// Gives the account a new security stamp: every device, this one included, has to log in again.
    func rotateSecurityStamp(password: String) async throws {
        var oldKey = try confirmedMasterKey(password)
        defer { oldKey.wipe() }
        _ = try await request("POST", "/api/accounts/security-stamp",
                              json: ["masterPasswordHash": try VWCrypto.masterHash(masterKey: oldKey, password: password)])
    }

    // MARK: Talking to the server

    private static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private func prelogin(_ email: String) async throws -> VWKDF {
        let data: Data
        do {
            data = try await perform("POST", "/identity/accounts/prelogin", json: ["email": email], token: nil)
        } catch let e as VWHTTPError where e.status == 404 {
            data = try await perform("POST", "/api/accounts/prelogin", json: ["email": email], token: nil)   // older servers
        }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = o["kdf"] as? Int, let iterations = o["kdfIterations"] as? Int else {
            throw VWError.failed("The server's answer isn't what Vaultwarden sends. Is the server address right?")
        }
        return VWKDF(type: type, iterations: iterations, memory: o["kdfMemory"] as? Int, parallelism: o["kdfParallelism"] as? Int)
    }

    /// A call that needs the login. A missing or expired access token is renewed with the refresh token first.
    private func request(_ method: String, _ path: String, json: Any? = nil,
                         raw: (body: Data, contentType: String)? = nil) async throws -> Data {
        if accessToken == nil { try await renewAccess() }
        do {
            return try await perform(method, path, json: json, raw: raw, token: accessToken)
        } catch let e as VWHTTPError where e.status == 401 {
            try await renewAccess()
            return try await perform(method, path, json: json, raw: raw, token: accessToken)
        }
    }

    private func renewAccess() async throws {
        let expired = VWError.failed("Your login with the server has expired. Log out in Settings (⌘,) and log in again.")
        guard let refresh = refreshToken else { throw expired }
        let data: Data
        do {
            data = try await perform("POST", "/identity/connect/token",
                                     form: ["grant_type": "refresh_token", "client_id": "desktop", "refresh_token": refresh],
                                     token: nil)
        } catch let e as VWHTTPError where e.status == 400 || e.status == 401 {
            accessToken = nil
            throw expired
        }
        guard let token = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = token["access_token"] as? String else { throw expired }
        accessToken = access
        if let renewed = token["refresh_token"] as? String, renewed != refresh {
            refreshToken = renewed
            if var stored = account, let key = userKey {
                stored.refreshToken = try VWCrypto.encrypt(renewed, with: key)
                try? VWStore.saveAccount(stored)
                account = stored
            }
        }
    }

    private static func formEncode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func perform(_ method: String, _ path: String, json: Any? = nil, form: [String: String]? = nil,
                         raw: (body: Data, contentType: String)? = nil, token: String?,
                         followRedirects: Bool = true) async throws -> Data {
        guard let url = URL(string: server + path) else { throw VWError.failed("The server address isn't valid.") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = raw == nil ? 30 : 120   // a file takes longer to send
        req.setValue("desktop", forHTTPHeaderField: "Bitwarden-Client-Name")
        req.setValue(Self.clientVersion, forHTTPHeaderField: "Bitwarden-Client-Version")
        req.setValue("7", forHTTPHeaderField: "Device-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let form {
            let text = form.map { Self.formEncode($0.key) + "=" + Self.formEncode($0.value) }.joined(separator: "&")
            req.httpBody = Data(text.utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else if let raw {
            req.httpBody = raw.body
            req.setValue(raw.contentType, forHTTPHeaderField: "Content-Type")
        }
        let session = URLSession(configuration: .ephemeral,
                                 delegate: VWTrust(pemFile: VW.customCACert, followRedirects: followRedirects), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw Self.transportError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw VWError.failed("The server's answer wasn't understood.") }
        guard (200..<300).contains(http.statusCode) else { throw VWHTTPError(status: http.statusCode, body: data) }
        return data
    }

    private static func transportError(_ error: Error) -> VWError {
        guard let e = error as? URLError else { return VWError.failed(error.localizedDescription) }
        switch e.code {
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .secureConnectionFailed:
            return VWError.failed("The server's certificate isn't trusted (\(e.localizedDescription)). In Keychain Access, open the certificate and set Trust to Always Trust, or choose its file in Settings (⌘,) > Server Certificate.")
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .timedOut, .networkConnectionLost, .dnsLookupFailed:
            return VWError.failed("Can't reach the server (\(e.localizedDescription)). Are you offline?")
        default:
            return VWError.failed(e.localizedDescription)
        }
    }
}
