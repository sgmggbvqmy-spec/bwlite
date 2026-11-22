// How the item list is sorted.

import SwiftUI
import AppKit

enum SortField: String, CaseIterable, Identifiable {
    case name = "Name"
    case created = "Created"
    case modified = "Modified"
    case username = "Username"
    case url = "Website"

    var id: String { rawValue }

    /// UserDefaults keys of the default sort chosen in Settings.
    static let fieldKey = "defaultSortField"
    static let ascendingKey = "defaultSortAscending"

    /// The default sort field and direction. A new window starts with them.
    static var savedDefault: SortField {
        SortField(rawValue: UserDefaults.standard.string(forKey: fieldKey) ?? "") ?? .name
    }
    static var savedAscending: Bool {
        UserDefaults.standard.object(forKey: ascendingKey) as? Bool ?? true
    }
}
