// Cards and rows, as in the macOS Passwords app.

import SwiftUI
import AppKit

/// Light rounded panel that holds rows separated by thin lines.
struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.panelFill)
            )
    }
}

/// Thin line between two rows, inset to line up with the text.
struct RowDivider: View {
    var body: some View {
        Divider()
    }
}

/// "Label ........ value" row. Only the value gets the hover frame, never the label.
/// - `hoverBox`: frame on hover for rows that aren't click-to-copy but are still interactive (links).
/// - `onTap`: click the value to copy it.
/// - `onHover`: told when the cursor enters or leaves the value (used to show the password).
struct InfoRow<Value: View>: View {
    let label: String
    let value: Value
    let interactive: Bool
    let onTap: (() -> Void)?
    let onHover: ((Bool) -> Void)?
    let flashes: Bool

    private init(label: String, interactive: Bool, onTap: (() -> Void)?,
                 onHover: ((Bool) -> Void)?, flashes: Bool = true, value: Value) {
        self.label = label
        self.interactive = interactive
        self.onTap = onTap
        self.onHover = onHover
        self.flashes = flashes
        self.value = value
    }

    /// A click runs `onClick` (e.g. opens a menu) and does not say "Copied".
    init(label: String, onClick: @escaping () -> Void, @ViewBuilder value: () -> Value) {
        self.init(label: label, interactive: true, onTap: onClick, onHover: nil, flashes: false, value: value())
    }

    init(label: String, hoverBox: Bool = false, @ViewBuilder value: () -> Value) {
        self.init(label: label, interactive: hoverBox, onTap: nil, onHover: nil, value: value())
    }

    init(label: String, onTap: @escaping () -> Void, @ViewBuilder value: () -> Value) {
        self.init(label: label, interactive: true, onTap: onTap, onHover: nil, value: value())
    }

    init(label: String, onTap: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
         @ViewBuilder value: () -> Value) {
        self.init(label: label, interactive: true, onTap: onTap, onHover: onHover, value: value())
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 16)
            value
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .hoverFrame(enabled: interactive, onTap: onTap, onHover: onHover, flashes: flashes)
                .offset(x: 5)             // text stays on the divider's end, the box sticks out
        }
        .padding(.vertical, 5.5)          // 37 pt rows, like Passwords
    }
}
