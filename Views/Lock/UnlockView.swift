// The lock screen.

import SwiftUI
import AppKit

struct UnlockField: View {
    let placeholder: String
    @Binding var text: String
    var secure = true   // false for e-mail and code fields
    let shakes: Int
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    @Environment(\.colorScheme) private var scheme

    private let radius: CGFloat = 6

    private var fill: Color {
        scheme == .light ? Color(.displayP3, red: 251 / 255, green: 251 / 255, blue: 251 / 255)
                         : Color(nsColor: .textBackgroundColor)
    }

    var body: some View {
        Group {
            if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
        }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused(focus)
            .onSubmit(onSubmit)
            .padding(.horizontal, 5)
            .frame(width: 220, height: 24)
            .overlay(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .padding(.leading, 5.5)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay {
                if focus.wrappedValue {
                    ZStack {
                        RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                            .padding(-3)
                        RoundedRectangle(cornerRadius: radius + 0.5, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
                            .padding(-1)
                    }
                }
            }
            .modifier(Shake(animatableData: CGFloat(shakes)))
    }
}

/// Locked screen, laid out like the macOS Passwords app: icon, title, one line of text, capsules.
struct UnlockView: View {
    @ObservedObject var vault: Vault
    @State private var password = ""
    @State private var shakes = 0
    /// With Touch ID set up, the screen first asks for a fingerprint; "Use Password…" shows the password field.
    @State private var usingPassword = false
    /// True while the system Touch ID sheet is up, so the button can show that it was pressed.
    @State private var waitingForTouchID = false
    @FocusState private var focused: Bool

    private var askingForTouchID: Bool { vault.touchIDKeySaved && !usingPassword }

    private func startTouchID() {
        guard !waitingForTouchID else { return }
        waitingForTouchID = true
        Task {
            await vault.unlockWithTouchID()
            waitingForTouchID = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Only a picture: the fingerprint badge while Touch ID is offered, the plain padlock with the
            // password field. Touch ID is asked for with the button below; nothing pops up by itself.
            LockIcon(fingerprint: askingForTouchID)
            Text("BwLite Is Locked")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 26)
            Text(askingForTouchID ? "Touch ID or enter your password to continue."
                                  : "Enter your master password to continue.")
                .font(.system(size: 16))
                .padding(.top, 4)
            if askingForTouchID {
                // A real button, so it is plain that Touch ID has to be asked for: lighter under the pointer,
                // darker and a little smaller while pressed, and "Waiting for Touch ID…" while the sheet is up.
                Button(action: startTouchID) {
                    HStack(spacing: 6) {
                        Image(systemName: "touchid")
                        Text(waitingForTouchID ? "Waiting for Touch ID…" : "Unlock with Touch ID")
                    }
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(waitingForTouchID)
                .padding(.top, 24)
                Button("Use Password…") { usingPassword = true }
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 10)
            } else {
                UnlockField(placeholder: "Password", text: $password, shakes: shakes,
                                focus: $focused, onSubmit: submit)
                    .task { focused = true }
                    .padding(.top, 28)
                // The way back, when Touch ID is set up and "Use Password…" was chosen.
                if vault.touchIDKeySaved {
                    Button("Use Touch ID…") {
                        password = ""
                        usingPassword = false
                    }
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 10)
                }
            }
            if vault.busy {
                ProgressView().controlSize(.small).padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(LockedScreenBackground())
    }

    private func submit() {
        guard !password.isEmpty, !vault.busy else { return }
        let pw = password
        password = ""   // don't keep the master password in the view any longer than needed
        Task {
            await vault.unlock(pw)
            if vault.state != .unlocked {
                // Like the original: a failed attempt is only shown by the shake, never as text.
                // The real message goes to the Console (search for "BwLite") in case it isn't a wrong password.
                NSLog("BwLite: unlock failed: %@", vault.error ?? "unknown error")
                withAnimation(.linear(duration: 0.5)) { shakes += 1 }
                focused = true
            }
        }
    }
}
