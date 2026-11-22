// The first screen: server, email, master password and two-step code.

import SwiftUI
import AppKit

/// First screen when nobody is logged in yet: email, master password and, if the account uses an authenticator
/// app, the current code. The server is set in Settings (⌘,).
struct LoginView: View {
    @ObservedObject var vault: Vault
    @AppStorage("email") private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var shakes = 0
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            LockIcon()
            Text("Log In to Bitwarden")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 26)
            Text("Enter your email and master password.")
                .font(.system(size: 16))
                .padding(.top, 4)
            VStack(spacing: 10) {
                UnlockField(placeholder: "Email", text: $email, secure: false, shakes: shakes,
                            focus: $emailFocused, onSubmit: { passwordFocused = true })
                UnlockField(placeholder: "Master Password", text: $password, shakes: shakes,
                            focus: $passwordFocused, onSubmit: submit)
                UnlockField(placeholder: "Two-Step Code (if enabled)", text: $code, secure: false, shakes: shakes,
                            focus: $codeFocused, onSubmit: submit)
            }
            .padding(.top, 28)
            if vault.busy {
                ProgressView().controlSize(.small).padding(.top, 14)
            }
            if let e = vault.error {
                Text(e)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.top, 14)
            } else if let n = vault.notice {
                Text(n)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.top, 14)
            }
            HStack(spacing: 4) {
                Text("Server: \(vault.serverDisplay)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if #available(macOS 14.0, *) {
                    SettingsLink { Text("Change…").font(.system(size: 11)) }
                        .buttonStyle(.link)
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(LockedScreenBackground())
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            if email.isEmpty { emailFocused = true } else { passwordFocused = true }
        }
    }

    private func submit() {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { emailFocused = true; return }
        guard !password.isEmpty, !vault.busy else { return }
        let pw = password
        let twoStep = code
        password = ""   // don't keep the master password in the view any longer than needed
        Task {
            await vault.login(email: address, password: pw, code: twoStep)
            if vault.state != .unlocked {
                withAnimation(.linear(duration: 0.5)) { shakes += 1 }
                passwordFocused = true
            }
        }
    }
}
