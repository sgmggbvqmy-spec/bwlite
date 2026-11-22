// A tile of the sidebar.

import SwiftUI
import AppKit

/// One tile of the folder grid in the sidebar: coloured round icon, count, name.
struct FolderTile: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? color : Color.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(selected ? Color.white : color))
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.panelFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
