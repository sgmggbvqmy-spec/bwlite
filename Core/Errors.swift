// The errors the core throws.

import Foundation

/// The error shown in the UI. Messages are written for people, not for logs.
nonisolated enum VWError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message.isEmpty ? "Something went wrong." : message
        }
    }
}

/// An answer other than 2xx from the server, kept whole so the login can look for "two-step code needed".
nonisolated struct VWHTTPError: LocalizedError {
    let status: Int
    let body: Data

    var json: [String: Any]? { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] }

    /// The server's own words when it gave any (Vaultwarden puts them in `message` / `errorModel`).
    var message: String {
        if let o = json {
            if let m = (o["errorModel"] as? [String: Any])?["message"] as? String, !m.isEmpty { return m }
            if let m = o["message"] as? String, !m.isEmpty { return m }
            if let m = o["error_description"] as? String, !m.isEmpty { return m }
            if let m = (o["error"] as? [String: Any])?["description"] as? String, !m.isEmpty { return m }
        }
        return "The server answered with an error (HTTP \(status))."
    }

    var errorDescription: String? { message }
}
