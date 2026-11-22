// Changing the master password or the email, and logging out of all devices.

import SwiftUI
import AppKit

/// One account change: asks for the current master password and what is new, then sends it to the server.
/// Success logs out of this Mac (see `Vault.endLogin`), so the sheet closes with the login screen behind it.
struct AccountChangeSheet: View {
    @ObservedObject var vault: Vault
    let change: AccountChange

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var hint = ""
    @State private var newEmail = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false
    @State private var error: String?

    private var title: String {
        switch change {
        case .password: return "Change Master Password"
        case .email:    return "Change Email"
        case .stamp:    return "Log Out of All Devices"
        }
    }

    private var explanation: String {
        switch change {
        case .password:
            return "Your vault is not re-encrypted, only the key that opens it is wrapped again. Every device, this Mac included, has to log in again afterwards."
        case .email:
            return "Vaultwarden sends a code to the new address. A server that can't send email sends nothing and doesn't check the code. The email is part of how your master key is made, so the key is wrapped again. Every device has to log in again afterwards."
        case .stamp:
            return "Ends the login of every device, this Mac included, by giving your account a new security stamp. Use it when a device may be lost or in the wrong hands. Then log in again here."
        }
    }

    private var actionTitle: String {
        switch change {
        case .password: return "Change Password"
        case .email:    return codeSent ? "Change Email" : "Send Code"
        case .stamp:    return "Log Out of All Devices"
        }
    }

    private var canRun: Bool {
        guard !working, !current.isEmpty else { return false }
        switch change {
        case .password: return !newPassword.isEmpty && newPassword == repeatPassword
        case .email:    return codeSent ? !code.trimmingCharacters(in: .whitespaces).isEmpty
                                        : !newEmail.trimmingCharacters(in: .whitespaces).isEmpty
        case .stamp:    return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            fields
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, role: change == .stamp ? .destructive : nil) { run() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
    }

    @ViewBuilder private var fields: some View {
        switch change {
        case .password:
            SecureField("Current master password", text: $current).textFieldStyle(.roundedBorder)
            SecureField("New master password", text: $newPassword).textFieldStyle(.roundedBorder)
            SecureField("Repeat the new master password", text: $repeatPassword).textFieldStyle(.roundedBorder)
            TextField("Password hint (optional, replaces the old one)", text: $hint).textFieldStyle(.roundedBorder)
            if !repeatPassword.isEmpty && repeatPassword != newPassword {
                Text("The two new passwords are different.").font(.callout).foregroundStyle(.red)
            }
        case .email:
            TextField("New email address", text: $newEmail).textFieldStyle(.roundedBorder).disabled(codeSent)
            SecureField("Current master password", text: $current).textFieldStyle(.roundedBorder).disabled(codeSent)
            if codeSent {
                Text("A code was requested for \(newEmail.trimmingCharacters(in: .whitespaces)). Enter it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Code from the email", text: $code).textFieldStyle(.roundedBorder)
            }
        case .stamp:
            SecureField("Current master password", text: $current).textFieldStyle(.roundedBorder)
        }
    }

    private func run() {
        guard canRun else { return }
        working = true
        error = nil
        Task { @MainActor in
            do {
                switch change {
                case .password:
                    try await vault.changePassword(current: current, new: newPassword, hint: hint)
                case .email:
                    if !codeSent {
                        try await vault.requestEmailChange(password: current, newEmail: newEmail)
                        codeSent = true
                        working = false
                        return
                    }
                    try await vault.changeEmail(password: current, newEmail: newEmail, code: code)
                case .stamp:
                    try await vault.logOutEverywhere(password: current)
                }
                // The change went through and this Mac is logged out: don't keep the passwords around.
                current = ""
                newPassword = ""
                repeatPassword = ""
                working = false
                dismiss()
            } catch {
                working = false
                self.error = error.localizedDescription
            }
        }
    }
}
