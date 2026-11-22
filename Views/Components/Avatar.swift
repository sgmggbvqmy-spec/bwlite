// The round icon of an item: its website's icon, or a letter.

import SwiftUI
import AppKit
import Combine

/// Where website icons are kept while the vault is unlocked: in memory only (nothing is written to disk), and
/// forgotten when the vault locks or you log out. They are asked for one at a time, a few at once, as rows appear.
@MainActor
final class IconStore: ObservableObject {
    static let shared = IconStore()

    /// The pictures found, by host name. A host without an entry has none (or hasn't been asked for yet).
    @Published private(set) var images: [String: NSImage] = [:]
    /// Counts up whenever the store is emptied, so views that show icons ask again.
    @Published private(set) var epoch = 0
    /// Fetches the picture of a host (the core, via the server). Set by `Vault`.
    var loader: ((String) async -> Data?)?

    private var asked: Set<String> = []
    private var waiting: [String] = []
    private var running = 0
    private var generation = 0
    private static let parallel = 4

    func image(forHost host: String?) -> NSImage? { host.flatMap { images[$0] } }

    /// Starts fetching the icon of a host, once. Does nothing while icons are switched off.
    func load(_ host: String) {
        guard VWIcons.enabled, loader != nil, !asked.contains(host) else { return }
        asked.insert(host)
        waiting.append(host)
        pump()
    }

    private func pump() {
        while running < Self.parallel, !waiting.isEmpty, let loader {
            let host = waiting.removeFirst()
            let round = generation
            running += 1
            Task { @MainActor in
                let data = await loader(host)
                guard round == generation else { return }   // emptied meanwhile: this answer is not wanted any more
                running -= 1
                if let data, let picture = NSImage(data: data) { images[host] = picture }
                pump()
            }
        }
    }

    /// Forgets every icon and every request (locking, logging out, switching icons off or on).
    func clear() {
        generation += 1
        images = [:]
        asked = []
        waiting = []
        running = 0
        epoch += 1
    }
}

/// Rounded-square icon with the first letter of the name, in system grey like the icon the
/// Passwords app shows for sites without one. A login shows the icon of its website instead when the server has
/// one (Settings > General > Website Icons); the letter stays until then, and when there is none.
struct Avatar: View {
    let name: String
    var size: CGFloat = 34
    /// True while the row is selected (blue highlight behind it).
    var highlighted = false
    /// An SF Symbol shown instead of the first letter (cards, identities, notes and SSH keys).
    var symbol: String?
    /// The host name of the website whose icon to show (a login's `iconHost`).
    var host: String?

    @ObservedObject private var icons: IconStore

    init(name: String, size: CGFloat = 34, highlighted: Bool = false, symbol: String? = nil, host: String? = nil) {
        self.name = name
        self.size = size
        self.highlighted = highlighted
        self.symbol = symbol
        self.host = host
        self.icons = IconStore.shared
    }

    private var letter: String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ZStack {
            if let picture = icons.image(forHost: host) {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Color.white)
                Image(nsImage: picture)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.14)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(highlighted ? Color.white.opacity(0.3) : Color(nsColor: .systemGray))
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(Color.white)
                } else {
                    Text(letter)
                        .font(.system(size: size * 0.74, weight: .regular))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .task(id: "\(host ?? "")|\(icons.epoch)") {
            if let host { icons.load(host) }
        }
    }
}
