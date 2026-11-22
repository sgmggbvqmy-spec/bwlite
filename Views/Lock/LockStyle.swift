// The look of the login and lock screens.

import SwiftUI
import AppKit

/// The app's icon: a dark rounded square with a blue key. (An original icon, not Apple's.)
struct AppIcon: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Color(white: 0.1))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "key.fill")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .rotationEffect(.degrees(-45))
            }
    }
}

/// App icon with a padlock badge, as on the macOS Passwords locked screen. With Touch ID the badge is a
/// red fingerprint instead (measured from the original: the glyph is about three quarters of the badge).
struct LockIcon: View {
    var fingerprint = false
    private let size: CGFloat = 65
    private let badge: CGFloat = 45

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppIcon(size: size)
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 4, y: 1)
                if fingerprint {
                    Image(systemName: "touchid")
                        .font(.system(size: badge * 0.68))
                        .foregroundStyle(Color(.displayP3, red: 235 / 255, green: 68 / 255, blue: 90 / 255))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: badge * 0.46))
                        .foregroundStyle(Color.black)   // measured: pure black in the original
                }
            }
            .frame(width: badge, height: badge)
            .offset(x: 16, y: 11)
        }
        .frame(width: size, height: size)
    }
}

/// Moves its content left and right, like the Mac's own "wrong password" shake.
/// Add 1 to `animatableData` inside `withAnimation(.linear(duration: 0.5))` to shake once (3 swings, back at rest).
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// The password field of the locked screen, as measured from the original (2x screenshot, Display P3):
/// 220 × 24 pt, corner radius 6, white (251) fill, "Password" in 13 pt at half-strength black, text starting
/// about 5 pt from the left edge, and while it has the cursor a 3.5 pt ring in the accent colour (a 1 pt stronger
/// line next to the field, then a lighter 2 pt band).
/// The grey pill button of the Passwords locked screen (measured: 220 x 27 pt, fully rounded).
struct PillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Color.primary)
            .frame(width: 220, height: 27)
            .background(
                Capsule().fill(scheme == .light
                               ? Color(.displayP3, red: 209 / 255, green: 211 / 255, blue: 212 / 255)
                               : Color.white.opacity(0.14))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// The main button of the locked screen (same size as the grey pill): accent colour, lighter under the pointer,
/// darker and a little smaller while pressed, faded when disabled.
struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryPill(configuration: configuration)
    }

    private struct PrimaryPill: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 220, height: 27)
                .background(Capsule().fill(Color.accentColor))
                .overlay(Capsule().fill(Color.white.opacity(hovering && enabled && !configuration.isPressed ? 0.18 : 0)))
                .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.25 : 0)))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.6)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

/// The locked screen's own flat colour. Measured in the original (Display P3): 226, 228, 229 everywhere,
/// title bar included. In dark mode the normal window colour is kept.
struct LockedScreenBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background(
            (scheme == .light ? Color(.displayP3, red: 226 / 255, green: 228 / 255, blue: 229 / 255)
                              : Color(nsColor: .windowBackgroundColor)).ignoresSafeArea())
    }
}
