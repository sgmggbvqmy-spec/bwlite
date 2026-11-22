// Asks for the authenticator setup key.

import SwiftUI
import AppKit

/// Asks for the setup key (or the otpauth:// link) that a website shows next to its QR code.
struct CodeSetupSheet: View {
    let onSet: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// A bare key may be typed in groups ("abcd efgh ..."): the spaces are not part of it.
    private var stored: String { Totp.stored(from: text) }
    private var valid: Bool { Totp(stored) != nil }

    var body: some View {
        VStack(spacing: 14) {
            Text("Set Up Code").font(.headline)
            Text("Enter the setup key the website shows next to its QR code, or paste its otpauth:// link.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Setup Key", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            if !trimmed.isEmpty && !valid {
                Text("This isn't a valid setup key.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Set Code") {
                    onSet(stored)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { focused = true }
    }
}
