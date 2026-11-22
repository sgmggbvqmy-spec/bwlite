// Hover and tap behaviour used by the rows.

import SwiftUI
import AppKit

/// Hover frame around ONE value (not the whole row), like the fields in the Passwords app:
/// a rounded outline appears while the cursor is over the value. With `onTap`, a click runs it
/// and the value says "Copied" for a moment.
struct HoverFrame: ViewModifier {
    let enabled: Bool
    let onTap: (() -> Void)?
    let onHover: ((Bool) -> Void)?
    let copiedAlignment: Alignment
    let flashes: Bool
    @State private var hovering = false
    @State private var copied = false

    @ViewBuilder func body(content: Content) -> some View {
        // "Copied" replaces the value, centred in the same box; a value shorter than the word gets a wider box.
        let framed = ZStack(alignment: copiedAlignment) {
                content.opacity(copied ? 0 : 1)
                if copied { Text("Copied").foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background {
                if enabled && hovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                onHover?(inside)
            }
        if let onTap {
            framed
                .onTapGesture {
                    onTap()
                    if flashes { flash() }
                }
        } else {
            framed
        }
    }

    private func flash() {
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

extension View {
    /// `onChange` without the macOS 14 deprecation warning that still builds for macOS 13.
    /// The closure receives the new value.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    func hoverFrame(enabled: Bool = true,
                    onTap: (() -> Void)? = nil,
                    onHover: ((Bool) -> Void)? = nil,
                    copiedAlignment: Alignment = .center,
                    flashes: Bool = true) -> some View {
        modifier(HoverFrame(enabled: enabled, onTap: onTap, onHover: onHover,
                            copiedAlignment: copiedAlignment, flashes: flashes))
    }
}
