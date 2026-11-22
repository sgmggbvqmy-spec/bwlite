// The password, passphrase and username generators.

import Foundation

/// The password, passphrase and username generators, with the options and the way of choosing characters of the
/// generators in the Bitwarden apps (the `bitwarden-generators` crate of Bitwarden's SDK). Nothing here is stored.
nonisolated enum VWGenerator {
    /// A uniformly distributed number from 0 up to (not including) `n`, without modulo bias. `n` can be up to 2^32.
    static func random(below n: Int) -> Int {
        precondition(n > 0 && n <= 1 << 32, "random(below:) needs a number from 1 to 2^32")
        let span = UInt64(1) << 32
        let limit = span - span % UInt64(n)
        while true {
            let value = VWPrim.random(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            if value < limit { return Int(value % UInt64(n)) }
        }
    }

    private static func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {   // Fisher-Yates
            items.swapAt(i, random(below: i + 1))
        }
    }

    private static func pick<T>(_ items: [T]) -> T { items[random(below: items.count)] }

    private static func capitalized(_ word: String) -> String { word.prefix(1).uppercased() + word.dropFirst() }

    // MARK: Password

    struct PasswordOptions: Equatable {
        var length = 16
        var uppercase = true
        var lowercase = true
        var numbers = true
        var special = false
        /// At least this many digits and symbols, when those are on. 0 asks for none in particular.
        var minNumbers = 1
        var minSpecial = 1
        /// Leaves out the letters and digits that look alike: I, O, l, 0 and 1.
        var avoidAmbiguous = false

        static let lengthRange = 5...128
        static let minimumRange = 0...9
        static let specialCharacters = Array("!@#$%^&*")

        /// How many characters have to be of a given kind: one capital and one small letter when those are on, and
        /// the minimums for digits and symbols.
        var requiredCount: Int {
            (uppercase ? 1 : 0) + (lowercase ? 1 : 0) + (numbers ? minNumbers : 0) + (special ? minSpecial : 0)
        }

        /// Why no password can be made with these options, or nil when one can.
        var problem: String? {
            if !(uppercase || lowercase || numbers || special) { return "Turn on at least one kind of character." }
            if !Self.lengthRange.contains(length) {
                return "The length must be \(Self.lengthRange.lowerBound) to \(Self.lengthRange.upperBound)."
            }
            if !Self.minimumRange.contains(minNumbers) || !Self.minimumRange.contains(minSpecial) {
                return "The minimums must be \(Self.minimumRange.lowerBound) to \(Self.minimumRange.upperBound)."
            }
            if requiredCount > length { return "The length is less than the \(requiredCount) characters that are required." }
            return nil
        }
    }

    /// A new random password: the required characters (at least one of each kind that is on, and the minimums), the
    /// rest from all the kinds that are on, all in a random order.
    static func password(_ options: PasswordOptions) throws -> String {
        if let problem = options.problem { throw VWError.failed(problem) }
        func pool(_ on: Bool, _ characters: String, ambiguous: String) -> [Character] {
            on ? characters.filter { !(options.avoidAmbiguous && ambiguous.contains($0)) } : []
        }
        let upper = pool(options.uppercase, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", ambiguous: "IO")
        let lower = pool(options.lowercase, "abcdefghijklmnopqrstuvwxyz", ambiguous: "l")
        let digits = pool(options.numbers, "0123456789", ambiguous: "01")
        let symbols = options.special ? PasswordOptions.specialCharacters : []
        let all = upper + lower + digits + symbols

        var characters: [Character] = []
        characters.reserveCapacity(options.length)
        for _ in 0..<(options.length - options.requiredCount) { characters.append(pick(all)) }
        let required: [(set: [Character], count: Int)] = [
            (upper, options.uppercase ? 1 : 0), (lower, options.lowercase ? 1 : 0),
            (digits, options.numbers ? options.minNumbers : 0), (symbols, options.special ? options.minSpecial : 0),
        ]
        for (set, count) in required {
            for _ in 0..<count { characters.append(pick(set)) }
        }
        shuffle(&characters)
        return String(characters)
    }

    // MARK: Passphrase

    struct PassphraseOptions: Equatable {
        var words = 6
        var separator = "-"
        /// Every word starts with a capital letter.
        var capitalize = false
        /// One digit is added to the end of one of the words.
        var includeNumber = false

        static let wordsRange = 3...20

        var problem: String? {
            Self.wordsRange.contains(words) ? nil
                : "A passphrase has \(Self.wordsRange.lowerBound) to \(Self.wordsRange.upperBound) words."
        }
    }

    /// A new random passphrase: words picked independently from the EFF list (so one can come up twice), then the
    /// digit, the capitals and the separator between the words.
    static func passphrase(_ options: PassphraseOptions) throws -> String {
        if let problem = options.problem { throw VWError.failed(problem) }
        let list = VWWordList.passphrase
        var words = (0..<options.words).map { _ in pick(list) }
        if options.includeNumber { words[random(below: words.count)] += String(random(below: 10)) }
        if options.capitalize { words = words.map(capitalized) }
        return words.joined(separator: options.separator)
    }

    // MARK: Username

    enum UsernameKind: String, CaseIterable, Identifiable {
        case plusAddressed = "Plus addressed email"
        case catchAll = "Catch-all email"
        case word = "Random word"
        var id: String { rawValue }
    }

    struct UsernameOptions: Equatable {
        var kind = UsernameKind.plusAddressed
        /// Your own address, for `plusAddressed`.
        var email = ""
        /// The domain that has a catch-all inbox, for `catchAll`.
        var domain = ""
        /// For `word`: the first letter is a capital.
        var capitalize = false
        /// For `word`: four digits are added to the end.
        var includeNumber = false

        var problem: String? {
            switch kind {
            case .plusAddressed:
                return VWGenerator.emailParts(email) == nil ? "Enter your email address, for example you@example.com." : nil
            case .catchAll:
                return VWGenerator.isDomain(domain) ? nil : "Enter the domain name, for example example.com."
            case .word:
                return nil
            }
        }
    }

    /// The part before and the part after the @ of an email address, or nil when it doesn't look like one.
    static func emailParts(_ email: String) -> (local: String, domain: String)? {
        let parts = email.trimmingCharacters(in: .whitespaces).split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[0].contains(where: \.isWhitespace),
              isDomain(String(parts[1])) else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    static func isDomain(_ text: String) -> Bool {
        let domain = text.trimmingCharacters(in: .whitespaces)
        return !domain.isEmpty && !domain.contains("@") && !domain.contains(where: \.isWhitespace)
    }

    /// Eight random lowercase letters and digits.
    private static func randomTag() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz1234567890")
        return String((0..<8).map { _ in pick(characters) })
    }

    /// A new username: `you+tag@example.com` (a tag added to your address, so mail still reaches you), `tag@domain`
    /// (for a catch-all inbox), or a random word.
    static func username(_ options: UsernameOptions) throws -> String {
        if let problem = options.problem { throw VWError.failed(problem) }
        switch options.kind {
        case .plusAddressed:
            let parts = emailParts(options.email)!
            return "\(parts.local)+\(randomTag())@\(parts.domain)"
        case .catchAll:
            return "\(randomTag())@\(options.domain.trimmingCharacters(in: .whitespaces))"
        case .word:
            var word = pick(VWWordList.eff)
            if options.capitalize { word = capitalized(word) }
            if options.includeNumber { word += String(format: "%04d", random(below: 10_000)) }
            return word
        }
    }
}
