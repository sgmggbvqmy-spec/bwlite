// The right column: one item, read-only.

import SwiftUI
import AppKit

struct DetailView: View {
    let entry: Entry
    let folderName: String?
    /// "Edit Websites" in the website menu starts editing. Nil (an item window): no such menu item.
    let onEditWebsites: (() -> Void)?
    /// Set for an item in Deleted: a card with Delete and Recover under the details.
    var deletedActions: DeletedActions?
    /// A click on an attachment: ask where to save it. Nil: the rows can't be clicked.
    var onSaveAttachment: ((ItemAttachment) -> Void)?
    /// The attachment that is being downloaded, if any.
    var downloadingAttachmentId: String?
    // Everything shown here is already in memory (the whole vault is loaded once at unlock), so
    // nothing runs when you click an item. Secrets stay as dots unless the cursor is over them.
    @State private var hoverPassword = false
    @State private var hoveredHistory: Int?
    /// The label of the secret row (card number, security code, ...) the cursor is over.
    @State private var hoveredSecret: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                mainCard
                if let deletedActions { deletedCard(deletedActions) }
                attachmentsCard
                historyCard
            }
            .padding(20)
        }
    }

    // MARK: cards

    private var header: some View {
        VStack(spacing: 10) {
            Avatar(name: entry.name, size: 60, symbol: entry.kind == .login ? nil : entry.kind.icon, host: entry.iconHost)
            Text(entry.name)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    /// Nothing is deleted on its own: the item stays here until it is recovered or deleted by hand.
    private func deletedCard(_ actions: DeletedActions) -> some View {
        Card {
            VStack(spacing: 12) {
                Text("This password was deleted. Recover it, or delete it permanently.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 9.5) {
                    Button("Delete", action: actions.delete)
                        .buttonStyle(CardButtonStyle(destructive: true))
                    Button("Recover", action: actions.recover)
                        .buttonStyle(CardButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var mainCard: some View {
        Card {
            header
            if entry.kind == .login { loginRows } else { otherRows }
            customRows
            // A SwiftUI builder takes at most 10 children, so the tail is grouped.
            Group {
                if let f = folderName {
                    RowDivider()
                    InfoRow(label: "Folder") { Text(f) }
                }
                RowDivider()
                InfoRow(label: "Modified") { Text(Self.format(entry.modified)) }
                RowDivider()
                InfoRow(label: "Created") { Text(Self.format(entry.created)) }
                RowDivider()
                notesBlock
            }
        }
    }

    @ViewBuilder private var loginRows: some View {
        RowDivider()
        if let u = entry.user, !u.isEmpty {
            InfoRow(label: "User Name", onTap: { Clipboard.copy(u, secret: false) }) {
                Text(u)
            }
            RowDivider()
        }
        // Hover to show the password, click to copy it.
        InfoRow(label: "Password", onTap: { copyPassword() }, onHover: { hoverPassword = $0 }) {
            Text(passwordText)
                .font(.system(.body, design: .monospaced))
        }
        // Verification code: computed from the item's authenticator key, click to copy.
        if let totp = entry.totp {
            RowDivider()
            InfoRow(label: "Code", onTap: { Clipboard.copy(totp.code(at: Date()), secret: true) }) {
                TotpValue(totp: totp)
            }
        }
        if !entry.urls.isEmpty {
            RowDivider()
            // Clicking the website opens a menu: Open / Copy / Edit.
            InfoRow(label: "Website", onClick: { showWebsiteMenu() }) {
                Text(websiteSummary)
            }
        }
    }

    private struct TypeRow: Identifiable {
        let label: String
        let value: String
        var secret = false
        var id: String { label }
    }

    /// The rows of a card, identity, SSH key, bank account, driver's license or passport: only the fields that
    /// have a value.
    private var typeRows: [TypeRow] {
        entry.kind.schema.compactMap { spec in
            guard let v = entry.data[spec.key], !v.isEmpty else { return nil }
            return TypeRow(label: spec.label, value: v, secret: spec.secret)
        }
    }

    /// A row you click to copy. A secret shows as dots until the cursor is over the row.
    private func copyRow(label: String, value: String, secret: Bool, hoverId: String) -> some View {
        InfoRow(label: label,
                onTap: { Clipboard.copy(value, secret: secret) },
                onHover: { inside in
                    if inside { hoveredSecret = hoverId } else if hoveredSecret == hoverId { hoveredSecret = nil }
                }) {
            Text(secret && hoveredSecret != hoverId ? String(repeating: "\u{2022}", count: 12) : value)
                .font(secret ? Font.system(.body, design: .monospaced) : Font.body)
        }
    }

    @ViewBuilder private var otherRows: some View {
        ForEach(typeRows) { row in
            RowDivider()
            copyRow(label: row.label, value: row.value, secret: row.secret, hoverId: row.label)
        }
    }

    /// The custom fields, after the item's own fields.
    @ViewBuilder private var customRows: some View {
        ForEach(entry.fields) { f in
            RowDivider()
            customRow(f)
        }
    }

    @ViewBuilder private func customRow(_ f: CustomField) -> some View {
        let label = f.name.isEmpty ? "Field" : f.name
        switch f.kind {
        case .text:
            copyRow(label: label, value: f.value, secret: false, hoverId: f.id.uuidString)
        case .hidden:
            copyRow(label: label, value: f.value, secret: true, hoverId: f.id.uuidString)
        case .boolean:
            InfoRow(label: label) { Text(f.value == "true" ? "Yes" : "No") }
        case .linked:
            InfoRow(label: label) { Text("Linked") }
        }
    }

    /// Like Passwords: an empty note shows the grey word "Notes"; a filled one shows just its text in the
    /// row. The text is selectable with the mouse; clicking it does not copy anything.
    @ViewBuilder private var notesBlock: some View {
        let notes = entry.notes ?? ""
        Text(notes.isEmpty ? "Notes" : notes)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10.5)
    }

    /// The files attached to the item; a click saves a copy (the download starts only then).
    @ViewBuilder private var attachmentsCard: some View {
        if !entry.attachments.isEmpty {
            Card {
                HStack(spacing: 6) {
                    Text("Attachments").font(.system(size: 13, weight: .semibold))
                    Text("\(entry.attachments.count)").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 14)
                ForEach(entry.attachments) { a in
                    RowDivider()
                    Button { onSaveAttachment?(a) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paperclip").foregroundStyle(.secondary)
                            Text(a.fileName).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 16)
                            Text(a.sizeText).foregroundStyle(.secondary)
                            if downloadingAttachmentId == a.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10.5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onSaveAttachment == nil)
                    .help("Save a copy of this file")
                }
            }
        }
    }

    @ViewBuilder private var historyCard: some View {
        if !entry.history.isEmpty {
            Card {
                HStack(spacing: 6) {
                    Text("Password History").font(.system(size: 13, weight: .semibold))
                    Text("\(entry.history.count)").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 14)
                ForEach(Array(entry.history.enumerated()), id: \.offset) { i, row in
                    RowDivider()
                    InfoRow(label: Self.format(row.date),
                            onTap: { Clipboard.copy(row.password, secret: true) },
                            onHover: { historyHover(i, $0) }) {
                        Text(hoveredHistory == i ? row.password : String(repeating: "•", count: 12))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: helpers

    private static func format(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    /// "https://www.example.com/" is shown as "www.example.com".
    private static func shortURL(_ s: String) -> String {
        var t = s
        let lower = s.lowercased()
        if lower.hasPrefix("https://") { t.removeFirst(8) } else if lower.hasPrefix("http://") { t.removeFirst(7) }
        if t.hasSuffix("/") { t.removeLast() }
        return t
    }

    // MARK: website

    /// "example.com", or "example.com and 1 more" when the item has several websites.
    private var websiteSummary: String {
        guard let first = entry.urls.first else { return "" }
        let host = Self.displayHost(first)
        let more = entry.urls.count - 1
        return more > 0 ? "\(host) and \(more) more" : host
    }

    /// "https://www.example.com/login" -> "example.com"
    private static func displayHost(_ s: String) -> String {
        var h = shortURL(s)
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        if h.lowercased().hasPrefix("www.") { h.removeFirst(4) }
        return h.isEmpty ? s : h
    }

    /// One website: Open / Copy. Several websites: one sub-menu per website. "Edit Websites" comes last.
    private func showWebsiteMenu() {
        let urls = entry.urls
        func actions(for url: String) -> [PopUpMenu.Item] {
            [.action("Open Website", { openWebsite(url) }),
             .action("Copy Website", { Clipboard.copy(url, secret: false) })]
        }
        var items: [PopUpMenu.Item]
        if urls.count == 1, let url = urls.first {
            items = actions(for: url)
        } else {
            items = urls.map { url -> PopUpMenu.Item in .submenu(Self.shortURL(url), actions(for: url)) }
        }
        if let onEditWebsites {
            items.append(.separator)
            items.append(.action("Edit Websites", onEditWebsites))
        }
        PopUpMenu.show(items)
    }

    /// Opens http(s) addresses in the default browser. A bare "example.com" gets https:// in front.
    private func openWebsite(_ s: String) {
        let full = s.contains("://") ? s : "https://" + s
        if let u = URL(string: full), ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(u)
        }
    }

    // MARK: password: hover to show, click to copy

    /// The real password while the cursor is over the row, dots otherwise.
    private var passwordText: String {
        if hoverPassword, let p = entry.login?.password, !p.isEmpty { return p }
        return String(repeating: "•", count: 16)
    }

    private func copyPassword() {
        if let p = entry.login?.password, !p.isEmpty { Clipboard.copy(p, secret: true) }
    }

    private func historyHover(_ i: Int, _ inside: Bool) {
        if inside {
            hoveredHistory = i
        } else if hoveredHistory == i {
            hoveredHistory = nil
        }
    }
}
