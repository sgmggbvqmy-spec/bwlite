// The Auto-Type search panel.

import SwiftUI
import AppKit
import Combine
import ApplicationServices

/// A floating panel that can take keyboard input without making BwLite the active app, so the app you
/// were typing in stays frontmost and receives the keystrokes afterwards.
final class AutoTypePanel: NSPanel {
    var onResign: (() -> Void)?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

@MainActor
final class AutoTypeModel: ObservableObject {
    @Published var query = "" { didSet { refresh(with: vault.entries) } }
    @Published private(set) var results: [Entry] = []
    @Published var selection = 0
    /// Whether macOS has allowed BwLite to send keystrokes.
    @Published var trusted = AXIsProcessTrusted()

    let vault: Vault
    private var bag = Set<AnyCancellable>()

    init(vault: Vault) {
        self.vault = vault
        // Also fills the list when the vault is unlocked from inside the panel.
        vault.$entries.sink { [weak self] list in self?.refresh(with: list) }.store(in: &bag)
    }

    var current: Entry? { results.indices.contains(selection) ? results[selection] : nil }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = max(0, min(results.count - 1, selection + delta))
    }

    func refresh(with entries: [Entry]) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = entries.filter { $0.kind == .login }   // only logins can be typed
        if !q.isEmpty {
            let tokens = q.split(separator: " ").map(String.init)
            list = list.filter { e in
                let haystack = ([e.name, e.user ?? ""] + e.urls).joined(separator: "\n").lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
            // Names that start with the query first, then names that contain it, then matches on user name or website.
            func rank(_ e: Entry) -> Int {
                let n = e.name.lowercased()
                return n.hasPrefix(q) ? 0 : (n.contains(q) ? 1 : 2)
            }
            list.sort {
                let (a, b) = (rank($0), rank($1))
                return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        results = Array(list.prefix(100))
        selection = 0
    }
}

struct AutoTypeView: View {
    @ObservedObject var model: AutoTypeModel
    @ObservedObject var vault: Vault
    let onRun: (AutoTypeAction) -> Void

    @State private var password = ""
    @State private var shakes = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch vault.state {
            case .unlocked: unlockedContent
            case .locked: lockedContent
            default: notReadyContent
            }
        }
        .frame(width: 560, height: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        // Put the cursor in the search or password field, also after unlocking from here.
        .task(id: vault.state) {
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }

    // MARK: Unlocked: search + list

    private var unlockedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                TextField("Search logins to type", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            Divider()
            if !model.trusted { accessBanner }
            resultList
            Divider()
            Text("↩ Type Both    ⌘↩ User Name    ⌥↩ Password    ⇧↩ Code    esc Close")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("macOS must allow BwLite to type for you (Accessibility).")
                .font(.system(size: 12))
            Spacer()
            Button("Allow…") { AutoType.requestAccess() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, entry in
                        row(entry, selected: index == model.selection)
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selection = index
                                onRun(.both)
                            }
                    }
                }
                .padding(6)
            }
            .overlay {
                if model.results.isEmpty {
                    Text(model.query.isEmpty ? "No logins" : "No Matches").foregroundStyle(.secondary)
                }
            }
            .onValueChange(of: model.selection) { _ in
                if let e = model.current { proxy.scrollTo(e.id) }
            }
        }
    }

    private func row(_ entry: Entry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Avatar(name: entry.name, size: 30, highlighted: selected, host: entry.iconHost)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let user = entry.user, !user.isEmpty {
                    Text(user)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if entry.totp != nil {
                Image(systemName: "lock.badge.clock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Color.accentColor : Color.clear))
    }

    // MARK: Locked / not ready

    private var lockedContent: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("BwLite Is Locked").font(.headline)
            UnlockField(placeholder: "Master Password", text: $password, shakes: shakes,
                            focus: $focused, onSubmit: submit)
            if vault.busy { ProgressView().controlSize(.small) }
            Spacer()
        }
        .padding(20)
    }

    private var notReadyContent: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(vault.state == .needsLogin ? "Not logged in. Log in from the BwLite window."
                                            : "BwLite isn't ready yet.")
                .foregroundStyle(.secondary)
            Button("Open BwLite") { AutoType.openApp() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard !password.isEmpty, !vault.busy else { return }
        let pw = password
        password = ""   // don't keep the master password in the view any longer than needed
        Task {
            await vault.unlock(pw)
            if vault.state != .unlocked {
                NSLog("BwLite: unlock failed: %@", vault.error ?? "unknown error")
                withAnimation(.linear(duration: 0.5)) { shakes += 1 }
                focused = true
            }
        }
    }
}
