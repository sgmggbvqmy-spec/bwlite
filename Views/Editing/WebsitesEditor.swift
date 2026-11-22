// Editing the websites of a login.

import SwiftUI
import AppKit

/// A website being edited: the address as typed and its match setting.
struct WebsiteDraft: Identifiable, Equatable {
    let id = UUID()
    var uri = ""
    /// A `URIMatch` raw value; nil = default.
    var match: Int?
}

extension Array where Element == WebsiteDraft {
    /// The websites to save: addresses trimmed, empty rows left out.
    var websites: [Website] {
        compactMap { draft in
            let address = draft.uri.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty ? nil : Website(uri: address, match: draft.match)
        }
    }
}

/// The websites of a login: one row per address with its own match setting (how the address is compared with
/// a page's address by autofill in the Bitwarden apps), and "Add Website".
struct WebsitesEditor: View {
    @Binding var sites: [WebsiteDraft]
    var labelColor: Color = .primary
    /// Puts the keyboard in the first address when the editor appears ("Edit Websites").
    var focusOnAppear = false

    @FocusState private var focused: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach($sites) { $site in
                if site.id != sites.first?.id { RowDivider() }
                row($site)
            }
            if !sites.isEmpty { RowDivider() }
            Button {
                let new = WebsiteDraft()
                sites.append(new)
                focused = new.id
            } label: {
                Label("Add Website", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10.5)
        }
        .task {
            guard focusOnAppear else { return }
            try? await Task.sleep(for: .milliseconds(150))
            if sites.isEmpty { sites.append(WebsiteDraft()) }
            focused = sites.first?.id
        }
    }

    private func row(_ site: Binding<WebsiteDraft>) -> some View {
        let id = site.wrappedValue.id
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text("Website").foregroundStyle(labelColor)
                TextField("example.com", text: site.uri)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .focused($focused, equals: id)
                Button {
                    sites.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove this website")
            }
            HStack(spacing: 8) {
                Text("Match").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                matchPicker(site)
            }
            .font(.callout)
        }
        .padding(.vertical, 10.5)
    }

    private func matchPicker(_ site: Binding<WebsiteDraft>) -> some View {
        let stored = site.wrappedValue.match
        return Picker("Match", selection: site.match) {
            Text("Default").tag(Int?.none)
            ForEach(URIMatch.allCases) { m in
                Text(m.title).tag(Int?.some(m.rawValue))
            }
            // A number this version doesn't know (another app wrote it) stays selectable, so it isn't lost.
            if let stored, URIMatch(rawValue: stored) == nil {
                Text(URIMatch.title(for: stored)).tag(Int?.some(stored))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        .help(stored.flatMap(URIMatch.init(rawValue:))?.summary ?? "The default: \(URIMatch.domain.title). \(URIMatch.domain.summary)")
    }
}
