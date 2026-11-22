// A message with Retry (the server can't be reached).

import SwiftUI
import AppKit

struct MessageView: View {
    let title: String
    let message: String
    let vault: Vault

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary).frame(maxWidth: 420)
            HStack {
                Button("Retry") { Task { await vault.start() } }
                if #available(macOS 14.0, *) {
                    SettingsLink { Text("Settings…") }
                }
            }
        }
        .padding()
    }
}
