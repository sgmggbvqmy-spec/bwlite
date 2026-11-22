// The colour of an item kind.

import SwiftUI
import AppKit

extension ItemKind {
    /// The colour of the Type tile.
    var color: Color {
        switch self {
        case .login: return Color(nsColor: .systemTeal)
        case .card: return Color(nsColor: .systemGreen)
        case .identity: return Color(nsColor: .systemPurple)
        case .secureNote: return Color(nsColor: .systemPink)
        case .sshKey: return Color(nsColor: .systemIndigo)
        case .bankAccount: return Color(nsColor: .systemMint)
        case .driversLicense: return Color(nsColor: .systemCyan)
        case .passport: return Color(nsColor: .systemRed)
        }
    }
}
