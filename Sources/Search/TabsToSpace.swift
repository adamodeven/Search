import AppKit
import SwiftUI

// Fork: tabs into another space, several at once.
//
// - Move to Space, right-clicked on a tab among several picked with ⌘ or ⇧,
//   moves every picked tab, not only the one right-clicked.
// - A tab carried down the column and let go over a space's icon in the row
//   at the column's foot goes to that space; one of several picked takes
//   the others with it, as in Arc. The icon it is over lights up while it
//   is carried there.
//
// Only this window's profile's spaces take tabs: a tab's page never goes
// under another profile's sign-ins (Profiles.swift), so another profile's
// icon doesn't light up and takes nothing.

@MainActor
extension Browser {
    /// The tabs a right-click or a drag on `tab` acts on: every tab picked,
    /// when it is one of several; otherwise itself.
    func pickedOrOnly(_ tab: Tab) -> [Tab] {
        guard selectedTabIDs.contains(tab.id), visibleSelectedTabCount > 1 else { return [tab] }
        return tabs.filter { selectedTabIDs.contains($0.id) }
    }

    /// Move to Space for `tab` and the others picked with it, in their order.
    func moveToSpace(_ tab: Tab, _ id: UUID, then: (() -> Void)? = nil) {
        let moving = pickedOrOnly(tab)
        clearTabSelection()
        for (n, each) in moving.enumerated() {
            move(each, toSpace: id, then: n == moving.count - 1 ? then : nil)
        }
    }
}

/// Where each space's icon is on screen, for a tab let go over one.
@MainActor
final class SpaceDrops: ObservableObject {
    static let shared = SpaceDrops()

    private struct Spot {
        weak var window: NSWindow?
        var rect: CGRect
    }

    /// By space, in the window's own coordinates (SwiftUI's global: from
    /// the top left of the window's content).
    private var spots: [UUID: Spot] = [:]
    /// The icon a tab is being carried over now.
    @Published private(set) var over: UUID?

    func place(_ space: UUID, at rect: CGRect, in window: NSWindow?) {
        spots[space] = Spot(window: window, rect: rect)
    }

    /// The space of this window's profile whose icon is under the pointer.
    private func space(under point: NSPoint, for browser: Browser) -> UUID? {
        guard let window = browser.window, let content = window.contentView else { return nil }
        let inWindow = window.convertPoint(fromScreen: point)
        let flipped = CGPoint(x: inWindow.x, y: content.bounds.height - inWindow.y)
        return spots.first { id, spot in
            spot.window === window && spot.rect.insetBy(dx: -2, dy: -4).contains(flipped)
                && id != browser.spaceID && browser.spaces.contains { $0.id == id }
        }?.key
    }

    /// While a tab is carried: light the icon it is over.
    func track(_ browser: Browser) {
        let now = browser.prefs.usesSpaces ? space(under: NSEvent.mouseLocation, for: browser) : nil
        if now != over { over = now }
    }

    /// A tab let go: true when it was over a space's icon, and went there
    /// with the others picked with it.
    func take(_ tab: Tab, in browser: Browser) -> Bool {
        defer { over = nil }
        guard browser.prefs.usesSpaces, tab.pin == nil || !tab.everywhere,
              let id = space(under: NSEvent.mouseLocation, for: browser) else { return false }
        // After the drag has finished putting itself away.
        DispatchQueue.main.async { browser.moveToSpace(tab, id) }
        return true
    }
}
