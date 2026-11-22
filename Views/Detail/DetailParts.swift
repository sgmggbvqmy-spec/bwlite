// Small parts of the right column.

import SwiftUI
import AppKit

/// What the two buttons under an item in Deleted do.
struct DeletedActions {
    let recover: () -> Void
    let delete: () -> Void
}

/// The small grey buttons of the card under a deleted item (measured from Passwords: 23 pt tall).
struct CardButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 13)
            .frame(height: 23)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Right column while several items are selected: a stack with a check mark and the count.
struct ItemsSelectedView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 26) {
            Image(systemName: "checkmark.rectangle.stack.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.primary.opacity(0.26))
            Text("\(count) Items Selected")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
