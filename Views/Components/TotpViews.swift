// Verification code views: the ring, the digits, the chips and the countdown.

import SwiftUI
import AppKit
import Combine

/// The little ring in front of the code, measured from Passwords: a pale track with a green arc that
/// grows clockwise from 12 o'clock (round ends, stroke about 3 pt) until the code changes.
struct TotpRing: View {
    let progress: Double
    var size: CGFloat = 16
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: lineWidth)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: min(progress, 1))
                    // The system green: the screenshot's pixels (101,196,102) are Display P3 values of exactly
                    // this colour. Typed in as sRGB numbers they would come out paler.
                    .stroke(Color.green,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }
}

/// "(ring) 570 690". Redraws on every whole second, so the code changes exactly when it expires.
struct TotpValue: View {
    let totp: Totp
    private let start = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            HStack(spacing: 8) {
                TotpRing(progress: totp.elapsed(at: context.date))
                Text(totp.formatted(at: context.date))
                    .font(.system(.body, design: .monospaced).weight(.medium))
            }
        }
    }
}

/// A code in the Codes list ("585 724") at the end of the row. The grey box only shows while the cursor
/// is over it, like the values in the detail pane. Click to copy the code.
struct CodeChip: View {
    let totp: Totp
    let selected: Bool
    @State private var hovering = false
    @State private var copied = false
    private let start = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(totp.formatted(at: context.date))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .opacity(copied ? 0 : 1)
                .overlay {
                    if copied { Text("Copied").font(.system(size: 13)) }
                }
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background {
                    if hovering {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture {
                    Clipboard.copy(totp.code(at: Date()), secret: true)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                }
        }
    }
}

/// The ring beside the "+" in the Codes list: how much of the current period has passed. It is driven by
/// a plain timer (a TimelineView may not tick inside a toolbar item).
struct CodesCountdown: View {
    let period: Int
    @State private var now = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let p = Double(max(1, period))
        TotpRing(progress: max(0, now.timeIntervalSince1970).truncatingRemainder(dividingBy: p) / p, size: 20)
            .onAppear { now = Date() }
            .onReceive(timer) { now = $0 }
    }
}
