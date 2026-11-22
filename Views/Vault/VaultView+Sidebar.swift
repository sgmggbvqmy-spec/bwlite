// The left column: tiles in sections, and the buttons at the bottom.

import SwiftUI
import AppKit

extension VaultView {
    /// A two-column grid of tiles.
    func tileGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            content()
        }
    }

    /// A section title with a little arrow: click it to fold the section's tiles away or bring them back. With
    /// `onAdd`, a small + at the right end of the title makes something new in the section.
    func sectionHeader(_ title: String, collapsed: Binding<Bool>, onAdd: (() -> Void)? = nil,
                               addHelp: String = "") -> some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { collapsed.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(collapsed.wrappedValue ? 0 : 90))
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapsed.wrappedValue ? "Show \(title)" : "Hide \(title)")
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .help(addHelp)
            }
        }
    }

    /// Leftmost column, in sections of tiles with a count each: All and TOTP, then Type (Login, Card, Identity,
    /// Secure Note, SSH Key), Folders (No Folder and one per folder), and Hidden Items (Archive, Deleted).
    var sidebar: some View {
        let counts = folderCounts
        let kindCounts = Dictionary(grouping: vault.entries, by: { $0.kind }).mapValues { $0.count }
        return ScrollView {
            VStack(spacing: 10) {
                tileGrid {
                    FolderTile(title: "All", icon: "key.fill", color: .blue,
                               count: vault.entries.count, selected: folderFilter == "") {
                        folderFilter = ""
                    }
                    FolderTile(title: "TOTP", icon: "lock.badge.clock.fill", color: Color(nsColor: .systemYellow),
                               count: vault.entries.filter { $0.totp != nil }.count,
                               selected: folderFilter == Self.codes) {
                        folderFilter = Self.codes
                    }
                }
                sectionHeader("Type", collapsed: $typeCollapsed)
                if !typeCollapsed {
                    tileGrid {
                        ForEach(ItemKind.sidebarOrder, id: \.self) { kind in
                            FolderTile(title: kind.title, icon: kind.icon, color: kind.color,
                                       count: kindCounts[kind] ?? 0, selected: folderFilter == Self.typeFilter(kind)) {
                                folderFilter = Self.typeFilter(kind)
                            }
                        }
                    }
                    .transition(.opacity)
                }
                sectionHeader("Folders", collapsed: $foldersCollapsed, onAdd: { showNewFolder = true }, addHelp: "New folder")
                if !foldersCollapsed {
                    tileGrid {
                        FolderTile(title: "No Folder", icon: "tray.fill", color: .gray,
                                   count: counts[""] ?? 0, selected: folderFilter == Self.noFolder) {
                            folderFilter = Self.noFolder
                        }
                        ForEach(vault.folders) { f in
                            FolderTile(title: f.name, icon: "folder.fill",
                                       color: Palette.folderColor(at: vault.folders.firstIndex(where: { $0.id == f.id }) ?? 0),
                                       count: counts[f.id ?? ""] ?? 0, selected: folderFilter == (f.id ?? "")) {
                                folderFilter = f.id ?? ""
                            }
                            .contextMenu {
                                Button("Rename Folder…") { renameTarget = f }
                                Divider()
                                Button("Delete Folder…", role: .destructive) {
                                    folderTarget = f
                                    confirmFolderDelete = true
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
                sectionHeader("Hidden Items", collapsed: $hiddenCollapsed)
                if !hiddenCollapsed {
                    tileGrid {
                        FolderTile(title: "Archive", icon: "archivebox.fill", color: Color(nsColor: .systemBrown),
                                   count: vault.archivedEntries.count, selected: folderFilter == Self.archive) {
                            folderFilter = Self.archive
                        }
                        FolderTile(title: "Deleted", icon: "trash.fill", color: .orange,
                                   count: vault.deletedEntries.count, selected: folderFilter == Self.deleted) {
                            folderFilter = Self.deleted
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 400)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
    }

    /// Bottom of the left column: offline notice, sync status, Lock, Refresh and Generator.
    var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let n = vault.notice {
                Text(n).font(.caption).foregroundStyle(.orange)
            }
            if let d = vault.lastSync {
                Text("Last sync: \(d.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    selection = []
                    Task { await vault.lock() }
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                }
                .labelStyle(.iconOnly)
                .help("Lock the vault")
                Button {
                    Task { await vault.reload(sync: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(vault.busy)
                .help("Sync with the server")
                Button {
                    showGenerator = true
                } label: {
                    Label { Text("Generator") } icon: { GeneratorIcon() }
                }
                .labelStyle(.iconOnly)
                .help("Password, passphrase and username generator")
                // Loading, syncing and saving all show up here, right of the refresh button.
                if vault.busy || editSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // The tiles scroll under this bar: blur them so the buttons and the sync text stay readable.
        .background(.regularMaterial)
    }
}
