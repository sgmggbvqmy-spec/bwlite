// The vault as the interface sees it: the state (needs login, locked, unlocked), the items, and every action.

import SwiftUI
import AppKit
import Combine

@MainActor
final class Vault: ObservableObject {
    enum State { case checking, problem, needsLogin, locked, unlocked }

    @Published var state: State = .checking { didSet { autoFillSync() } }
    @Published var entries: [Entry] = [] { didSet { autoFillSync() } }
    @Published var folders: [Folder] = []   // real folders only, sorted by name
    @Published var deletedEntries: [Entry] = []   // the trash
    @Published var archivedEntries: [Entry] = []   // the Archive
    @Published var busy = false
    @Published var error: String?
    /// Non-fatal message, e.g. "sync failed, showing cached data".
    @Published var notice: String?
    @Published var lastSync: Date?
    /// The server you log in to ("" = none chosen yet) and the logged-in account's email.
    @Published var serverURL = ""
    @Published var userEmail: String?

    /// The keys and tokens live inside this object, in memory only, from unlocking until locking.
    private let core = VWCore()

    /// Whether the account has been looked up already.
    private var started = false

    /// The first look at the account, whatever number of windows share this vault.
    func startOnce() async {
        guard !started else { return }
        started = true
        IconStore.shared.loader = { [core] host in await core.icon(forHost: host) }
        startAutoLock()
        if !touchIDEnabled { TouchID.delete() }
        touchIDKeySaved = touchIDEnabled && TouchID.hasSavedKey
        await start()
    }

    // MARK: Touch ID

    /// True while a key is kept for Touch ID, so the lock screen offers it.
    @Published private(set) var touchIDKeySaved = false
    private var touchIDPrompting = false

    private var touchIDEnabled: Bool { UserDefaults.standard.bool(forKey: VW.touchIDKey) }

    /// Keeps the saved key in step with the switch in Settings: saves it once unlocked with the master
    /// password, deletes it when the switch is off. Called after those unlocks and when the switch changes.
    func syncTouchID() async {
        guard touchIDEnabled else {
            if touchIDKeySaved { TouchID.delete(); touchIDKeySaved = false }
            return
        }
        guard state == .unlocked, !touchIDKeySaved, let key = await core.userKeyData() else { return }
        touchIDKeySaved = TouchID.save(key)
    }

    /// Asks for a fingerprint, then unlocks with the saved key. On a cancel or a mismatch nothing happens,
    /// and the master password field is still there.
    func unlockWithTouchID() async {
        guard state == .locked, touchIDKeySaved, !busy, !touchIDPrompting else { return }
        touchIDPrompting = true
        defer { touchIDPrompting = false }
        guard await TouchID.authenticate(reason: "unlock your vault") else { return }
        guard let key = TouchID.load() else {
            touchIDKeySaved = false
            NSLog("BwLite: the key for Touch ID is gone from the keychain")
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            show(try await core.unlock(userKey: key))
            activity.touch()
            state = .unlocked
        } catch {
            TouchID.delete()
            touchIDKeySaved = false
            NSLog("BwLite: Touch ID unlock failed: %@", error.localizedDescription)
        }
    }

    // MARK: Auto-lock

    private let activity = VWActivity()
    private var activityMonitor: Any?
    private var autoLockTask: Task<Void, Never>?

    /// Locks the vault when BwLite hasn't been used for the time set in Settings (never, if set to Never).
    /// "Used" means a key press, a click or a scroll in one of its windows, or unlocking. After the Mac
    /// has slept for longer than that time, the next check locks it.
    private func startAutoLock() {
        guard autoLockTask == nil else { return }
        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [activity] event in
            activity.touch()
            return event
        }
        autoLockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                await self.lockIfIdle()
            }
        }
    }

    private func lockIfIdle() async {
        guard state == .unlocked, !busy else { return }
        guard let minutes = VW.autoLockMinutes, activity.idleSeconds() >= Double(minutes) * 60 else { return }
        await lock()
    }

    func start() async {
        busy = true
        error = nil
        state = .checking
        defer { busy = false }
        let s = await core.status()
        apply(s)
        state = s.hasAccount ? .locked : .needsLogin
    }

    /// Takes the account details from the core.
    private func apply(_ s: VWStatus) {
        lastSync = s.lastSync
        serverURL = s.server
        userEmail = s.email
    }

    private func refreshAccount() async {
        apply(await core.status())
    }

    /// "vault.example.com/" -> "https://vault.example.com". Empty stays empty.
    static func normalizedServer(_ text: String) -> String { VW.normalizedServer(text) }

    /// What to show for the server: its host name.
    var serverDisplay: String {
        serverURL.isEmpty ? "not set" : (URL(string: serverURL)?.host ?? serverURL)
    }

    /// Returns an error message, or nil when it worked.
    func setServer(_ text: String) async -> String? {
        let problem = await core.setServer(text)
        await refreshAccount()
        return problem
    }

    /// Logs in, then loads the vault the same way `unlock` does.
    func login(email: String, password: String, code: String) async {
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do {
            let snap = try await core.login(email: email, password: password, code: code)
            show(snap)
            await refreshAccount()
            activity.touch()
            state = .unlocked
            await syncTouchID()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Account changes

    // The server gives the account a new security stamp with each of these, which ends this Mac's login (and every
    // other device's). So after one has worked, the account is removed from this Mac and the login screen says why.

    private func endLogin(because message: String) async {
        _ = await logout()
        notice = message
    }

    func changePassword(current: String, new: String, hint: String) async throws {
        guard state == .unlocked else { throw VWError.failed("Unlock BwLite first.") }
        try await core.changePassword(current: current, new: new, hint: hint)
        await endLogin(because: "Your master password was changed. Log in again with the new one.")
    }

    /// Asks the server to send a code to the new address.
    func requestEmailChange(password: String, newEmail: String) async throws {
        guard state == .unlocked else { throw VWError.failed("Unlock BwLite first.") }
        try await core.requestEmailChange(password: password, newEmail: newEmail)
    }

    func changeEmail(password: String, newEmail: String, code: String) async throws {
        guard state == .unlocked else { throw VWError.failed("Unlock BwLite first.") }
        try await core.changeEmail(password: password, newEmail: newEmail, code: code)
        let address = VWCrypto.normalizedEmail(newEmail)
        UserDefaults.standard.set(address, forKey: "email")   // the login screen starts with the new address
        await endLogin(because: "Your email was changed to \(address). Log in again with it and your master password.")
    }

    func logOutEverywhere(password: String) async throws {
        guard state == .unlocked else { throw VWError.failed("Unlock BwLite first.") }
        try await core.rotateSecurityStamp(password: password)
        await endLogin(because: "All devices were logged out. Log in again with your master password.")
    }

    /// Returns an error message, or nil when it worked.
    func logout() async -> String? {
        await core.logout()
        Clipboard.clearSecret()
        IconStore.shared.clear()
        TouchID.delete()
        touchIDKeySaved = false
        entries = []
        deletedEntries = []
        archivedEntries = []
        folders = []
        error = nil
        notice = nil
        userEmail = nil
        lastSync = nil
        state = .needsLogin
        return nil
    }

    func unlock(_ password: String) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            // Only the local, encrypted copy of the vault is read, so this also works offline.
            show(try await core.unlock(password: password))
            activity.touch()
            state = .unlocked
            await syncTouchID()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Puts a decrypted vault on screen.
    private func show(_ snap: VWSnapshot) {
        setEntries(snap.entries)
        deletedEntries = snap.deleted.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        archivedEntries = snap.archived.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        setFolders(snap.folders)
        lastSync = snap.lastSync
        if snap.skipped > 0 {
            notice = "\(snap.skipped) item\(snap.skipped == 1 ? "" : "s") couldn't be decrypted and \(snap.skipped == 1 ? "is" : "are") not shown."
        }
    }

    func reload(sync: Bool) async {
        guard state == .unlocked else { state = .locked; return }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do {
            if sync {
                do {
                    show(try await core.sync())
                } catch {
                    // Typically offline, or the server is unreachable. Not fatal: the local copy still works.
                    let why = String(error.localizedDescription.prefix(160))
                    show(try await core.snapshot())
                    notice = "Sync failed (\(why)). Showing data from the last successful sync."
                }
            } else {
                show(try await core.snapshot())
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func lock() async {
        await core.lock()
        Clipboard.clearSecret()
        IconStore.shared.clear()
        entries = []
        deletedEntries = []
        archivedEntries = []
        folders = []
        error = nil
        notice = nil
        state = .locked
    }

    /// Creates a login on the server, then syncs and reloads the list. Returns the new item's id.
    func createLogin(name: String, username: String, password: String, websites: [Website],
                     notes: String, folderId: String?, totp: String = "",
                     fields: [CustomField] = []) async throws -> String {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        let id = try await core.createLogin(name: name, username: username, password: password,
                                            websites: websites, notes: notes, folderId: folderId,
                                            totp: totp, fields: fields)
        await reload(sync: true)
        return id
    }

    /// Creates any other kind of item, then syncs and reloads the list. Returns the new item's id.
    func createItem(kind: ItemKind, name: String, notes: String, folderId: String?,
                    data: [String: String], fields: [CustomField]) async throws -> String {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        let id = try await core.createItem(kind: kind, name: name, notes: notes, folderId: folderId,
                                           data: data, fields: fields)
        await reload(sync: true)
        return id
    }

    /// Downloads one attachment, decrypted. Nothing changes in the vault.
    func downloadAttachment(itemId: String, attachmentId: String) async throws -> (name: String, data: Data) {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        return try await core.downloadAttachment(itemId: itemId, attachmentId: attachmentId)
    }

    /// Removes and attaches files (see `VWCore.changeAttachments`), then syncs and reloads the list.
    func changeAttachments(itemId: String, remove: [String], add: [(token: UUID, url: URL)]) async -> AttachmentChanges {
        guard state == .unlocked else { return AttachmentChanges(failure: "The vault is locked.") }
        let result = await core.changeAttachments(itemId: itemId, remove: remove, add: add)
        await reload(sync: true)
        return result
    }

    /// Saves changes to an item that is not a login, then syncs and reloads the list.
    func updateItem(id: String, name: String, notes: String, data: [String: String],
                    fields: [CustomField]) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.updateItem(id: id, name: name, notes: notes, data: data, fields: fields)
        await reload(sync: true)
    }

    /// Saves changes to an existing login on the server, then syncs and reloads the list.
    func updateLogin(id: String, name: String, username: String, password: String,
                     websites: [Website], notes: String, totp: String, fields: [CustomField]? = nil) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.updateLogin(id: id, name: name, username: username, password: password,
                                   websites: websites, notes: notes, totp: totp, fields: fields)
        await reload(sync: true)
    }

    /// Moves an item into another folder on the server, then syncs and reloads the list.
    func moveItem(id: String, folderId: String?) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.moveItem(id: id, folderId: folderId)
        await reload(sync: true)
    }

    /// Takes an item out of the trash, then syncs and reloads the lists.
    func restoreItem(id: String) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.restoreItem(id: id)
        await reload(sync: true)
    }

    /// Deletes an item for good (it can't be restored), then syncs and reloads the lists.
    func deleteItemForever(id: String) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.deleteItemForever(id: id)
        await reload(sync: true)
    }

    /// Runs one change on several items, then syncs and reloads the lists once. Stops at the first failure
    /// (the lists are still reloaded, so they show what did get done) and passes the error on.
    private func forEachItem(_ ids: [String], _ change: (String) async throws -> Void) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        var failure: Error?
        for id in ids {
            do { try await change(id) } catch { failure = error; break }
        }
        await reload(sync: true)
        if let failure { throw failure }
    }

    func moveItems(ids: [String], folderId: String?) async throws {
        try await forEachItem(ids) { try await core.moveItem(id: $0, folderId: folderId) }
    }

    func deleteItems(ids: [String]) async throws {
        try await forEachItem(ids) { try await core.deleteItem(id: $0) }
    }

    func restoreItems(ids: [String]) async throws {
        try await forEachItem(ids) { try await core.restoreItem(id: $0) }
    }

    func deleteItemsForever(ids: [String]) async throws {
        try await forEachItem(ids) { try await core.deleteItemForever(id: $0) }
    }

    func archiveItems(ids: [String]) async throws {
        try await forEachItem(ids) { try await core.archiveItem(id: $0) }
    }

    func unarchiveItems(ids: [String]) async throws {
        try await forEachItem(ids) { try await core.unarchiveItem(id: $0) }
    }

    /// Makes a folder, then syncs and reloads the lists. Returns the new folder's id.
    func createFolder(name: String) async throws -> String {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        let id = try await core.createFolder(name: name)
        await reload(sync: true)
        return id
    }

    /// Renames a folder, then syncs and reloads the lists.
    func renameFolder(id: String, name: String) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.renameFolder(id: id, name: name)
        await reload(sync: true)
    }

    /// Removes a folder (its items stay, without a folder), then syncs and reloads the lists.
    func deleteFolder(id: String) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.deleteFolder(id: id)
        await reload(sync: true)
    }

    /// Moves an item to the trash on the server, then syncs and reloads the list.
    func deleteItem(id: String) async throws {
        guard state == .unlocked else { throw VWError.failed("The vault is locked.") }
        try await core.deleteItem(id: id)
        await reload(sync: true)
    }

    private func setFolders(_ list: [Folder]) {
        let used = Set(entries.compactMap(\.folderId))
        folders = list.filter { f in
            guard let id = f.id, !id.isEmpty, id != "null",
                  !id.allSatisfy({ $0 == "0" || $0 == "-" }) else { return false }
            if f.name == "No Folder" && !used.contains(id) { return false }
            return true
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The folder's name, or nil for items without a folder.
    func folderName(for entry: Entry) -> String? {
        guard let id = entry.folderId else { return nil }
        return folders.first { $0.id == id }?.name
    }

    private func setEntries(_ list: [Entry]) {
        entries = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Hands the unlocked vault to the AutoFill bridge (see AutoFillHost.swift), and empties it on lock.
    /// Compiled only when the Xcode target defines the AUTOFILL flag; the plain swiftc build in the GitHub workflow skips it.
    private func autoFillSync() {
        #if AUTOFILL
        AutoFillHost.shared.publish(entries, unlocked: state == .unlocked)
        #endif
    }
}
