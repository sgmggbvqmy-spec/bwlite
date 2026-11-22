// A custom field of an item.

import Foundation

/// A custom field of an item: a name and a value, which is plain text, hidden text, a yes/no box, or a link
/// to one of the item's own fields.
nonisolated struct CustomField: Identifiable, Equatable {
    nonisolated enum Kind: Int {
        case text = 0, hidden = 1, boolean = 2, linked = 3
    }

    var id = UUID()
    var name = ""
    var value = ""
    var kind = Kind.text
    /// Only for `.linked`: which field of the item it shows. Kept as it is, never edited here.
    var linkedId: Int?
}
