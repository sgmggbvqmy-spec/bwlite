// A row of the item list.

import SwiftUI
import AppKit

/// One row of the item list, drawn by hand so it looks like the Passwords app: a rounded highlight
/// inset from the column edges, and a thin separator that starts under the text. Every row is 56 pt tall.
struct ItemRow: View {
    let entry: Entry
    let selected: Bool
    /// The row above / below is selected too: this row's highlight joins theirs (square corners on that side).
    var selectedAbove = false
    var selectedBelow = false
    let showsSeparator: Bool
    /// Set in the Codes list: the live verification code shows at the end of the row.
    var code: Totp?

    private var subtitle: String { entry.subtitle }

    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: entry.name, size: 30, highlighted: selected,
                   symbol: entry.kind == .login ? nil : entry.kind.icon, host: entry.iconHost)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .lineLimit(1)
                // A space keeps the two-line layout even when there is no username or URL.
                Text(subtitle.isEmpty ? " " : subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let code { CodeChip(totp: code, selected: selected) }
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background {
            if selected {
                if selectedAbove || selectedBelow {
                    RoundedCorners(top: selectedAbove ? 0 : 10, bottom: selectedBelow ? 0 : 10)
                        .fill(Color.accentColor)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Divider()
                    .padding(.leading, 10 + 30 + 14)   // under the text, not under the icon
                    .padding(.trailing, 10)
            }
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

/// A rectangle whose top corners and bottom corners have their own radius (0 = square).
struct RoundedCorners: Shape {
    var top: CGFloat
    var bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        let t = min(top, rect.height / 2)
        let b = min(bottom, rect.height / 2)
        var p = Path()
        // A corner with radius 0 is just the point itself.
        func corner(_ point: CGPoint, then next: CGPoint, radius: CGFloat) {
            if radius > 0 {
                p.addArc(tangent1End: point, tangent2End: next, radius: radius)
            } else {
                p.addLine(to: point)
            }
        }
        p.move(to: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        corner(CGPoint(x: rect.maxX, y: rect.minY), then: CGPoint(x: rect.maxX, y: rect.minY + t), radius: t)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - b))
        corner(CGPoint(x: rect.maxX, y: rect.maxY), then: CGPoint(x: rect.maxX - b, y: rect.maxY), radius: b)
        p.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        corner(CGPoint(x: rect.minX, y: rect.maxY), then: CGPoint(x: rect.minX, y: rect.maxY - b), radius: b)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + t))
        corner(CGPoint(x: rect.minX, y: rect.minY), then: CGPoint(x: rect.minX + t, y: rect.minY), radius: t)
        p.closeSubpath()
        return p
    }
}
