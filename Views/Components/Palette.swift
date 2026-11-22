// Colours.

import SwiftUI
import AppKit

enum Palette {
    /// Apple's own system colours, used one after another for the folder tiles
    /// (the Passwords app does the same for its categories). Change the list to taste.
    static let folderColors: [Color] = [.green, .orange, .teal, .purple, .pink, .yellow]

    static func folderColor(at index: Int) -> Color {
        folderColors[index % folderColors.count]
    }
}

extension Color {
    /// The faint grey behind tiles and cards. NSColor.quaternarySystemFill exists only on macOS 14+,
    /// older systems get a close match from the label colour.
    static var panelFill: Color {
        if #available(macOS 14.0, *) { return Color(nsColor: .quaternarySystemFill) }
        return Color(nsColor: .labelColor).opacity(0.06)
    }
}
