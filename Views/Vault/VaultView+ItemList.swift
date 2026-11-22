// The middle column: the item list and its toolbar.

import SwiftUI
import AppKit

extension VaultView {
    /// Middle column: title + item count above the list, sort menu and "+" in the toolbar.
    var itemList: some View {
        let rows = visible
        let lines = listLines(for: rows)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(lines) { line in
                        switch line {
                        case .header(let text):
                            // Measured from Passwords: 11 pt semibold in grey, a hairline underneath.
                            VStack(spacing: 0) {
                                Text(text)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 16.5)
                                    .padding(.bottom, 6)
                                Divider()
                                    .padding(.leading, 16)
                                    .padding(.trailing, 20)
                            }
                            .padding(.top, line.id == lines.first?.id ? 0 : 14)
                            .padding(.bottom, 10)
                        case .row(let e, let prev, let next):
                            // No separator under the selected row or just above it, like Passwords. Selected
                            // rows right next to each other form one highlight, without rounded corners between.
                            let isSelected = selection.contains(e.id)
                            let nextSelected = next.map { selection.contains($0) } ?? false
                            ItemRow(entry: e,
                                    selected: isSelected,
                                    selectedAbove: isSelected && (prev.map { selection.contains($0) } ?? false),
                                    selectedBelow: isSelected && nextSelected,
                                    showsSeparator: next != nil && !isSelected && !nextSelected,
                                    code: folderFilter == Self.codes ? e.totp : nil)
                                .id(e.id)
                                .onTapGesture { click(e) }
                                .contextMenu { rowMenu(for: e) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onValueChange(of: selection) { ids in
                // Keeps the selected row on screen when using the arrow keys.
                if ids.count == 1, let id = ids.first { proxy.scrollTo(id) }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 480)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .overlay {
            if rows.isEmpty && !vault.busy {
                Text(query.isEmpty ? "No Items" : "No Results").foregroundStyle(.secondary)
            }
        }
        .toolbar {
            codesRing(period: rows.first?.totp?.period ?? 30)
            ToolbarItemGroup(placement: .primaryAction) {
                if folderFilter != Self.codes { sortMenu }
                // Nothing is added to the trash by hand, so there is no "+" in Deleted.
                if folderFilter != Self.deleted {
                    Menu {
                        ForEach(ItemKind.sidebarOrder, id: \.self) { kind in
                            Button {
                                newItemKind = kind
                                showNewItem = true
                            } label: {
                                Label(kind.title, systemImage: kind.icon)
                            }
                        }
                    } label: {
                        Label("New Item", systemImage: "plus")
                    }
                    .menuIndicator(.hidden)
                    .help("Add item")
                }
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    /// The countdown ring of the Codes list stands on its own in the toolbar: no glass background, and
    /// not in the same capsule as the "+". It is an item of its own, empty in the other lists.
    @ToolbarContentBuilder func codesRing(period: Int) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                if folderFilter == Self.codes { CodesCountdown(period: period) }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortField) {
                ForEach(SortField.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.inline)
            Picker("Order", selection: $sortAscending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuIndicator(.hidden)
        .help("Sort")
    }
}
