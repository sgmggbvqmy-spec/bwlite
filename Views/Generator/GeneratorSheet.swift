// The generator: a password, a passphrase or a username.

import SwiftUI
import AppKit

/// The generate icon of the Bitwarden apps: two arrows going round, with an asterisk in the middle.
struct GeneratorIcon: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .overlay(Image(systemName: "asterisk").font(.system(size: 6, weight: .heavy)))
    }
}

/// The generator: a password, a passphrase or a username, made with the options of the Bitwarden apps. It opens from
/// the button at the bottom left of the sidebar (Copy), and from the password field of a new login (`onUse`: the
/// button then hands the result to the field). Nothing is saved in the vault. The options are remembered between
/// launches, the result is not.
struct GeneratorSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case password = "Password", passphrase = "Passphrase", username = "Username"
        var id: String { rawValue }
    }

    /// The tabs: all three from the sidebar, only password and passphrase from a password field.
    let modes: [Mode]
    /// Set when the generator was opened from a password field: "Use this password" hands the result over.
    let onUse: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    // Password
    @AppStorage("generatorLength") private var length = 16
    @AppStorage("generatorUppercase") private var uppercase = true
    @AppStorage("generatorLowercase") private var lowercase = true
    @AppStorage("generatorNumbers") private var numbers = true
    @AppStorage("generatorSpecial") private var special = false
    @AppStorage("generatorMinNumbers") private var minNumbers = 1
    @AppStorage("generatorMinSpecial") private var minSpecial = 1
    @AppStorage("generatorAvoidAmbiguous") private var avoidAmbiguous = false
    // Passphrase
    @AppStorage("generatorWords") private var words = 6
    @AppStorage("generatorSeparator") private var separator = "-"
    @AppStorage("generatorCapitalize") private var capitalizeWords = false
    @AppStorage("generatorIncludeNumber") private var includeNumber = false
    // Username
    @AppStorage("generatorUsernameKind") private var usernameKind = VWGenerator.UsernameKind.plusAddressed
    @AppStorage("generatorEmail") private var email = ""
    @AppStorage("generatorDomain") private var domain = ""
    @AppStorage("generatorUsernameCapitalize") private var capitalizeUsername = false
    @AppStorage("generatorUsernameNumber") private var usernameNumber = false

    @State private var result = ""
    @State private var problem: String?
    @State private var copied = false

    init(modes: [Mode] = Mode.allCases, onUse: ((String) -> Void)? = nil) {
        self.modes = modes
        self.onUse = onUse
        // From the sidebar the tab used last comes first; from a password field the first of `modes`.
        let saved = onUse == nil ? UserDefaults.standard.string(forKey: "generatorMode").flatMap(Mode.init(rawValue:)) : nil
        _mode = State(initialValue: saved.flatMap { modes.contains($0) ? $0 : nil } ?? modes[0])
    }

    private var passwordOptions: VWGenerator.PasswordOptions {
        VWGenerator.PasswordOptions(length: length, uppercase: uppercase, lowercase: lowercase, numbers: numbers,
                                    special: special, minNumbers: minNumbers, minSpecial: minSpecial,
                                    avoidAmbiguous: avoidAmbiguous)
    }

    private var passphraseOptions: VWGenerator.PassphraseOptions {
        VWGenerator.PassphraseOptions(words: words, separator: separator, capitalize: capitalizeWords,
                                      includeNumber: includeNumber)
    }

    private var usernameOptions: VWGenerator.UsernameOptions {
        VWGenerator.UsernameOptions(kind: usernameKind, email: email, domain: domain,
                                    capitalize: capitalizeUsername, includeNumber: usernameNumber)
    }

    /// How many of the four kinds of character are on (the last one can't be switched off).
    private var kindsOn: Int { [uppercase, lowercase, numbers, special].filter { $0 }.count }

    /// The shortest password the options allow: it has to hold the required characters.
    private var shortestLength: Int {
        max(VWGenerator.PasswordOptions.lengthRange.lowerBound, passwordOptions.requiredCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generator").font(.title2.weight(.semibold))
            if modes.count > 1 {
                Picker("Type", selection: $mode) {
                    ForEach(modes) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            resultBox
            Button {
                if let onUse { use(onUse) } else { copy() }
            } label: {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(problem != nil || result.isEmpty)
            switch mode {
            case .password: passwordCard
            case .passphrase: passphraseCard
            case .username: usernameCard
            }
            HStack {
                Spacer()
                Button(onUse == nil ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            // Stored values that are out of range (edited by hand) are put back in range.
            words = min(max(words, VWGenerator.PassphraseOptions.wordsRange.lowerBound),
                        VWGenerator.PassphraseOptions.wordsRange.upperBound)
            minNumbers = min(max(minNumbers, VWGenerator.PasswordOptions.minimumRange.lowerBound),
                             VWGenerator.PasswordOptions.minimumRange.upperBound)
            minSpecial = min(max(minSpecial, VWGenerator.PasswordOptions.minimumRange.lowerBound),
                             VWGenerator.PasswordOptions.minimumRange.upperBound)
            length = min(max(length, shortestLength), VWGenerator.PasswordOptions.lengthRange.upperBound)
            regenerate()
        }
        // The result is not kept: it is dropped when the sheet closes.
        .onDisappear { result = "" }
        .onValueChange(of: mode) { newMode in
            if onUse == nil { UserDefaults.standard.set(newMode.rawValue, forKey: "generatorMode") }
            regenerate()
        }
        .onValueChange(of: passwordOptions) { _ in regenerate() }
        .onValueChange(of: passphraseOptions) { _ in regenerate() }
        .onValueChange(of: usernameOptions) { _ in regenerate() }
        // More required characters make the password longer, as in the Bitwarden apps.
        .onValueChange(of: passwordOptions.requiredCount) { required in
            if length < required { length = required }
        }
    }

    // MARK: result

    private var resultBox: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let problem {
                    Text(problem).foregroundStyle(.secondary)
                } else {
                    Text(shown(result)).font(.system(size: 17, design: .monospaced))
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                regenerate()
            } label: {
                GeneratorIcon().foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Generate a new one")
            if onUse != nil {
                Button {
                    copy()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy")
                .disabled(problem != nil || result.isEmpty)
            }
        }
        .padding(12)
        .frame(minHeight: 64, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    /// The result as text. In a password the digits are blue and the symbols red, as in the Bitwarden apps.
    private func shown(_ text: String) -> AttributedString {
        var out = AttributedString()
        for character in text {
            var piece = AttributedString(String(character))
            if mode == .password {
                if character.isNumber {
                    piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.blue
                } else if VWGenerator.PasswordOptions.specialCharacters.contains(character) {
                    piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.red
                }
            }
            out.append(piece)
        }
        return out
    }

    private func regenerate() {
        do {
            switch mode {
            case .password: result = try VWGenerator.password(passwordOptions)
            case .passphrase: result = try VWGenerator.passphrase(passphraseOptions)
            case .username: result = try VWGenerator.username(usernameOptions)
            }
            problem = nil
        } catch {
            result = ""
            problem = error.localizedDescription
        }
    }

    private var primaryTitle: String {
        guard onUse != nil else { return copied ? "Copied" : "Copy" }
        switch mode {
        case .password: return "Use this password"
        case .passphrase: return "Use this passphrase"
        case .username: return "Use this username"
        }
    }

    /// Hands the result to whoever opened the generator, and closes it.
    private func use(_ handOver: (String) -> Void) {
        guard problem == nil, !result.isEmpty else { return }
        handOver(result)
        dismiss()
    }

    /// A password or passphrase is copied like any secret: marked as concealed and cleared again after 30 seconds.
    private func copy() {
        guard problem == nil, !result.isEmpty else { return }
        Clipboard.copy(result, secret: mode != .username)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    // MARK: options

    private var passwordCard: some View {
        // Grouped so that no ViewBuilder block has more than ten views.
        card {
            Group {
                row("Length") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { Double(length) }, set: { length = Int($0.rounded()) }),
                               in: Double(shortestLength)...Double(VWGenerator.PasswordOptions.lengthRange.upperBound),
                               step: 1)
                            .frame(width: 170)
                        Text("\(length)").monospacedDigit().frame(width: 30, alignment: .trailing)
                    }
                }
                Divider()
                switchRow("A-Z", $uppercase, locked: uppercase && kindsOn == 1)
                Divider()
                switchRow("a-z", $lowercase, locked: lowercase && kindsOn == 1)
            }
            Group {
                Divider()
                switchRow("0-9", $numbers, locked: numbers && kindsOn == 1)
                Divider()
                switchRow("!@#$%^&*", $special, locked: special && kindsOn == 1)
            }
            Group {
                Divider()
                row("Minimum numbers") {
                    Stepper(value: $minNumbers, in: VWGenerator.PasswordOptions.minimumRange) {
                        Text("\(minNumbers)").monospacedDigit()
                    }
                    .disabled(!numbers)
                }
                Divider()
                row("Minimum special") {
                    Stepper(value: $minSpecial, in: VWGenerator.PasswordOptions.minimumRange) {
                        Text("\(minSpecial)").monospacedDigit()
                    }
                    .disabled(!special)
                }
                Divider()
                switchRow("Avoid ambiguous characters", $avoidAmbiguous)
            }
        }
    }

    private var passphraseCard: some View {
        card {
            row("Number of words") {
                Stepper(value: $words, in: VWGenerator.PassphraseOptions.wordsRange) {
                    Text("\(words)").monospacedDigit()
                }
            }
            Divider()
            row("Word separator") {
                TextField("", text: $separator)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
            }
            Divider()
            switchRow("Capitalize", $capitalizeWords)
            Divider()
            switchRow("Include number", $includeNumber)
        }
    }

    private var usernameCard: some View {
        card {
            row("Type") {
                Picker("", selection: $usernameKind) {
                    ForEach(VWGenerator.UsernameKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            Divider()
            switch usernameKind {
            case .plusAddressed:
                row("Email address") {
                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            case .catchAll:
                row("Domain name") {
                    TextField("example.com", text: $domain)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            case .word:
                switchRow("Capitalize", $capitalizeUsername)
                Divider()
                switchRow("Include number", $usernameNumber)
            }
        }
    }

    // MARK: building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func switchRow(_ title: String, _ isOn: Binding<Bool>, locked: Bool = false) -> some View {
        row(title) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(locked)
        }
    }
}
