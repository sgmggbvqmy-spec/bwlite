// A line of the item list: a date heading or an item.

import SwiftUI
import AppKit

/// One line of the item list: a date heading or an item.
enum ListLine: Identifiable {
    case header(String)
    /// `prev` and `next` are the ids of the items right above and below in the same section
    /// (none at the ends of a section: no separator after the last one, no joining highlight).
    case row(Entry, prev: String?, next: String?)

    var id: String {
        switch self {
        case .header(let title): return "header: " + title
        case .row(let entry, _, _): return entry.id
        }
    }
}
