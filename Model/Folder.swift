// A folder, and the date format of the server.

import Foundation

/// One folder of the vault. The "No Folder" tile of the list isn't a real folder, so it is not in here.
nonisolated struct Folder: Identifiable, Decodable {
    let id: String?
    let name: String
}

nonisolated enum VWDate {
    /// Dates look like 2024-05-01T12:34:56.789Z (with or without fractional seconds).
    static func parse(_ s: String?) -> Date? {
        guard var text = s else { return nil }
        // Vaultwarden writes microseconds (.987266); cut to milliseconds, the form the parser is sure to read.
        if let dot = text.firstIndex(of: "."),
           let end = text[text.index(after: dot)...].firstIndex(where: { !$0.isNumber }) {
            let digits = text[text.index(after: dot)..<end]
            if digits.count > 3 { text.replaceSubrange(text.index(after: dot)..<end, with: digits.prefix(3)) }
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
