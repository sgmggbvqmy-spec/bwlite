// Sorting and grouping the items of the list.

import SwiftUI
import AppKit

extension VaultView {
    // MARK: sorting

    /// Ties are always broken by name (ascending), whatever the sort direction.
    func byName(_ a: Entry, _ b: Entry) -> Bool {
        let r = a.name.localizedStandardCompare(b.name)
        return r == .orderedSame ? a.id < b.id : r == .orderedAscending
    }

    /// Sorts by a text field. Items without a value always go last, in either direction.
    func orderedByText(_ list: [Entry], _ key: (Entry) -> String?) -> [Entry] {
        var present: [(entry: Entry, text: String)] = []
        var missing: [Entry] = []
        for e in list {
            if let t = key(e), !t.isEmpty { present.append((e, t)) } else { missing.append(e) }
        }
        present.sort { a, b in
            let r = a.text.localizedStandardCompare(b.text)
            if r == .orderedSame { return byName(a.entry, b.entry) }
            return sortAscending ? r == .orderedAscending : r == .orderedDescending
        }
        return present.map { $0.entry } + missing.sorted(by: byName)
    }

    /// Same, for dates.
    func orderedByDate(_ list: [Entry], _ key: (Entry) -> Date?) -> [Entry] {
        var present: [(entry: Entry, date: Date)] = []
        var missing: [Entry] = []
        for e in list {
            if let d = key(e) { present.append((e, d)) } else { missing.append(e) }
        }
        present.sort { a, b in
            if a.date == b.date { return byName(a.entry, b.entry) }
            return sortAscending ? a.date < b.date : a.date > b.date
        }
        return present.map { $0.entry } + missing.sorted(by: byName)
    }

    func ordered(_ list: [Entry]) -> [Entry] {
        if folderFilter == Self.codes { return list.sorted(by: byName) }
        switch sortField {
        case .name:     return orderedByText(list) { $0.name }
        case .username: return orderedByText(list) { $0.user }
        case .url:      return orderedByText(list) { $0.sortURL }
        case .created:  return orderedByDate(list) { $0.created }
        case .modified: return orderedByDate(list) { $0.modified }
        }
    }

    var visible: [Entry] { ordered(filtered) }

    /// Heading of the section a date belongs to: Today, Yesterday, Previous 7 Days, Previous 30 Days,
    /// then the year. Later dates always land in an earlier-or-equal section, so sorted rows stay together.
    static func dateHeading(_ date: Date?, now: Date) -> String {
        guard let date else { return "No Date" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if date >= today { return "Today" }
        if let d = cal.date(byAdding: .day, value: -1, to: today), date >= d { return "Yesterday" }
        if let d = cal.date(byAdding: .day, value: -7, to: today), date >= d { return "Previous 7 Days" }
        if let d = cal.date(byAdding: .day, value: -30, to: today), date >= d { return "Previous 30 Days" }
        return String(cal.component(.year, from: date))
    }

    /// The sorted items as list lines. Sorted by date (Created / Modified), they get date headings
    /// like in Passwords; otherwise it is a plain list.
    func listLines(for rows: [Entry]) -> [ListLine] {
        let dateOf: ((Entry) -> Date?)?
        if folderFilter == Self.codes {
            dateOf = nil
        } else {
            switch sortField {
            case .created:  dateOf = { $0.created }
            case .modified: dateOf = { $0.modified }
            default:        dateOf = nil
            }
        }
        let now = Date()
        let headings: [String?] = rows.map { e in dateOf.map { Self.dateHeading($0(e), now: now) } }
        var lines: [ListLine] = []
        for (i, e) in rows.enumerated() {
            if let h = headings[i], i == 0 || headings[i - 1] != h { lines.append(.header(h)) }
            let sameSection = i + 1 < rows.count && headings[i + 1] == headings[i]
            let sameAbove = i > 0 && headings[i - 1] == headings[i]
            lines.append(.row(e, prev: sameAbove ? rows[i - 1].id : nil, next: sameSection ? rows[i + 1].id : nil))
        }
        return lines
    }
}
