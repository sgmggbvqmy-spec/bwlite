// What is selected: clicks, Command-A and the arrow keys.

import SwiftUI
import AppKit

extension VaultView {
    // MARK: arrow keys (the hand-made list has no built-in keyboard navigation)

    /// A click on a row: Command adds or removes it, Shift selects everything from the last click to it.
    func click(_ e: Entry) {
        guard editingId == nil else { return }
        let flags = NSEvent.modifierFlags
        let list = visible
        if flags.contains(.command) {
            if selection.contains(e.id) { selection.remove(e.id) } else { selection.insert(e.id) }
            anchor = e.id
        } else if flags.contains(.shift), let start = anchor,
                  let from = list.firstIndex(where: { $0.id == start }),
                  let to = list.firstIndex(where: { $0.id == e.id }) {
            selection = Set(list[min(from, to)...max(from, to)].map { $0.id })
        } else {
            selection = [e.id]
            anchor = e.id
        }
    }

    /// Command-A: every item in the list on screen.
    func selectAll() {
        let list = visible
        guard !list.isEmpty, editingId == nil else { return }
        selection = Set(list.map { $0.id })
        anchor = list.first?.id
    }

    func moveSelection(by delta: Int) {
        let list = visible
        guard !list.isEmpty, editingId == nil else { return }
        // From the item clicked last, or else the first selected one; an arrow key leaves one item selected.
        let current = list.firstIndex(where: { $0.id == anchor && selection.contains($0.id) })
            ?? list.firstIndex(where: { selection.contains($0.id) })
        let next = current.map { min(max($0 + delta, 0), list.count - 1) } ?? (delta > 0 ? 0 : list.count - 1)
        selection = [list[next].id]
        anchor = list[next].id
    }

    /// Up/Down arrows move the selection and Command-A selects everything, except while you are typing
    /// in the search field.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let typing = NSApp.keyWindow?.firstResponder is NSText
            if modifiers == .command, event.charactersIgnoringModifiers == "a", !typing {
                selectAll()
                return nil
            }
            let plain = modifiers.isEmpty
            let isArrow = event.keyCode == 125 || event.keyCode == 126   // down, up
            guard plain, isArrow, !typing else { return event }
            moveSelection(by: event.keyCode == 125 ? 1 : -1)
            return nil
        }
    }

    func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}
