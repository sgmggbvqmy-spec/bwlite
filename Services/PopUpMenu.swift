// A native pop-up menu at the mouse pointer.

import Foundation
import AppKit

/// Shows a native pop-up menu at the mouse pointer (used when you click a website).
@MainActor
enum PopUpMenu {
    indirect enum Item {
        case action(String, () -> Void)
        case submenu(String, [Item])
        case separator
    }

    private final class Target: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    static func show(_ items: [Item]) {
        _ = build(items).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func build(_ items: [Item]) -> NSMenu {
        let menu = NSMenu()
        for item in items {
            switch item {
            case .separator:
                menu.addItem(NSMenuItem.separator())
            case .action(let title, let run):
                let target = Target(run)
                let menuItem = NSMenuItem(title: title, action: #selector(Target.fire), keyEquivalent: "")
                menuItem.target = target
                menuItem.representedObject = target   // a menu item doesn't retain its target, so keep it alive here
                menu.addItem(menuItem)
            case .submenu(let title, let children):
                let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                menuItem.submenu = build(children)
                menu.addItem(menuItem)
            }
        }
        return menu
    }
}
