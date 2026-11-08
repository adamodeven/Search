import AppKit
import Combine

// Fork: ⌃Z takes back the last thing done to the tabs, as in Arc. A tab
// moved, pinned or unpinned, put in a group or taken out, a group made;
// tabs closed (they come back, as ⇧⌘T brings them); tabs moved to another
// space (they come back here). Each ⌃Z one step further back.
//
// The window's row is watched rather than every way of changing it hooked:
// whenever the window changes, the row is looked at once the change is done,
// and if its tabs are the same tabs in another arrangement, the arrangement
// before is kept as a step. A drag counts once, when it is let go. Tabs
// opened, or the row changing to another space's, are no step.

@MainActor
final class TabUndo {
    private static var watches: [ObjectIdentifier: TabUndo] = [:]

    private weak var browser: Browser?
    private var last: Arrangement
    private var ghosts: Int
    private var steps: [Step] = []
    private var scheduled = false
    private var quiet = 0
    /// Where a drag started from, until it is let go.
    private var base: Arrangement?
    private var bag: AnyCancellable?

    private static let most = 50

    private enum Step {
        case arrangement(Arrangement)
        /// This many closes, each brought back as ⇧⌘T would.
        case reopen(Int)
        /// These tabs went from `from` to `to`.
        case spaced([UUID], from: UUID, to: UUID)
    }

    private init(_ browser: Browser) {
        self.browser = browser
        last = Arrangement(browser)
        ghosts = browser.ghosts.count
        bag = browser.objectWillChange.sink { [weak self] _ in self?.soon() }
    }

    /// Start keeping steps for this window (from its column's appearing).
    static func watch(_ browser: Browser) {
        let key = ObjectIdentifier(browser)
        if watches[key]?.browser == nil { watches[key] = TabUndo(browser) }
        watches = watches.filter { $0.value.browser != nil }
    }

    private static func of(_ browser: Browser) -> TabUndo? {
        watch(browser)
        return watches[ObjectIdentifier(browser)]
    }

    /// Several changes as one step: whatever `change` does to the row.
    static func step(_ browser: Browser, _ change: () -> Void) {
        guard let undo = of(browser) else { return change() }
        undo.look()
        undo.quiet += 1
        let before = undo.last
        let closed = browser.ghosts.count
        change()
        undo.quiet -= 1
        let now = Arrangement(browser)
        undo.ghosts = browser.ghosts.count
        if browser.ghosts.count > closed {
            undo.push(.reopen(undo.units(since: closed)))
            // What else it did (a pin put down before it closed) is the reopening's.
        } else if now.space == before.space, now.ids == before.ids, now != before {
            undo.push(.arrangement(before))
        }
        undo.last = now
    }

    /// Tabs gone to another space, to come back from there (TabsToSpace.swift).
    static func moved(_ ids: [UUID], from: UUID, to: UUID, in browser: Browser) {
        guard let undo = of(browser), !ids.isEmpty else { return }
        undo.push(.spaced(ids, from: from, to: to))
    }

    /// ⌃Z, from the window's keys. False for anything else, or while a
    /// field of the window's own is being typed in.
    static func key(_ event: NSEvent, flags: NSEvent.ModifierFlags, in browser: Browser) -> Bool {
        guard flags.intersection([.command, .option, .control, .shift]) == [.control],
              event.charactersIgnoringModifiers?.lowercased() == "z" || event.keyCode == 6 else { return false }
        if let editor = browser.window?.firstResponder as? NSTextView, editor.isEditable { return false }
        guard let undo = of(browser) else { return false }
        undo.undo()
        return true
    }

    // MARK: - watching

    private func soon() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.scheduled = false
            self?.look()
        }
    }

    private func look() {
        guard quiet == 0, let browser else { return }
        let now = Arrangement(browser)
        let closed = browser.ghosts.count
        defer { ghosts = closed }
        if closed > ghosts {
            push(.reopen(units(since: ghosts)))
            last = now
            base = nil
            return
        }
        guard now.space == last.space, now.ids == last.ids else {
            last = now
            base = nil
            return
        }
        guard now != last else { return settle() }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            // Still being carried: the step is from where it started.
            if base == nil { base = last }
            last = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.look() }
            return
        }
        push(.arrangement(base ?? last))
        base = nil
        last = now
    }

    /// A drag let go with nothing more changing after it.
    private func settle() {
        guard let base else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.look() }
            return
        }
        self.base = nil
        if base != last, base.space == last.space, base.ids == last.ids { push(.arrangement(base)) }
    }

    /// The closes among the ghosts after the first `count`: one for each
    /// tab closed alone, one for each bulk close.
    private func units(since count: Int) -> Int {
        guard let browser else { return 0 }
        let fresh = browser.ghosts.dropFirst(count)
        var batches = Set<UUID>()
        return fresh.filter { ghost in ghost.batch.map { batches.insert($0).inserted } ?? true }.count
    }

    private func push(_ step: Step) {
        steps.append(step)
        if steps.count > TabUndo.most { steps.removeFirst(steps.count - TabUndo.most) }
    }

    // MARK: - going back

    private func undo() {
        guard let browser else { return }
        look()
        guard let step = steps.popLast() else {
            NSSound.beep()
            return
        }
        quiet += 1
        defer {
            quiet -= 1
            last = Arrangement(browser)
            ghosts = browser.ghosts.count
            base = nil
        }
        switch step {
        case .reopen(let count):
            for _ in 0..<count {
                guard let ghost = browser.ghosts.last else { break }
                browser.reopen(ghost)
            }
        case .arrangement(let was):
            if browser.spaceID != was.space { browser.switchSpace(to: was.space) }
            guard browser.spaceID == was.space else { return }
            was.restore(in: browser)
        case .spaced(let ids, let from, let to):
            let here = browser.spaceID
            if here != to { browser.switchSpace(to: to) }
            guard browser.spaceID == to else { return }
            for id in ids {
                if let tab = browser.tabs.first(where: { $0.id == id }) { browser.move(tab, toSpace: from) }
            }
            browser.switchSpace(to: here == to ? to : here)
        }
    }
}

/// The row as far as ⌃Z cares: which tabs, in what order, pinned how and
/// in which group, and the groups' names.
@MainActor
private struct Arrangement: Equatable {
    struct Place: Equatable {
        var pin: String?
        var listed: Bool
        var home: URL?
        var group: UUID?
    }

    struct Group: Equatable {
        var id: UUID
        var name: String
    }

    let space: UUID
    let order: [UUID]
    let places: [UUID: Place]
    let groups: [Group]

    var ids: Set<UUID> { Set(order) }

    init(_ browser: Browser) {
        space = browser.spaceID
        order = browser.tabs.map(\.id)
        places = Dictionary(browser.tabs.map { ($0.id, Place(pin: $0.pin, listed: $0.listed, home: $0.home, group: $0.groupID)) },
                            uniquingKeysWith: { a, _ in a })
        groups = browser.tabGroups.map { Group(id: $0.id, name: $0.name) }
    }

    func restore(in browser: Browser) {
        // The groups first, so tabs have theirs to go back into.
        let open = Dictionary(browser.tabGroups.map { ($0.id, $0.collapsed) }, uniquingKeysWith: { a, _ in a })
        browser.tabGroups = groups.map { TabGroup(id: $0.id, name: $0.name, collapsed: open[$0.id] ?? false) }
        for tab in browser.tabs {
            guard let place = places[tab.id] else { continue }
            if place.pin != nil, tab.pin == nil {
                browser.pin(tab, listed: place.listed)
            } else if place.pin == nil, tab.pin != nil {
                browser.unpin(tab)
            }
            if let letter = place.pin { tab.pin = letter }
            if tab.pin != nil, tab.listed != place.listed { browser.setListed(tab, place.listed) }
            if tab.pin != nil, let home = place.home { tab.home = home }
            if tab.pin == nil, tab.groupID != place.group {
                browser.move(tab, toGroup: place.group)
            }
        }
        // Then each in its place, from the top.
        let wanted = order.filter { id in browser.tabs.contains { $0.id == id } }
        for (index, id) in wanted.enumerated() {
            guard browser.tabs.indices.contains(index), browser.tabs[index].id != id,
                  let tab = browser.tabs.first(where: { $0.id == id }) else { continue }
            browser.move(tab, to: index)
        }
        // A group the step left with no tabs goes again.
        let used = Set(browser.tabs.compactMap(\.groupID))
        for group in browser.tabGroups where !used.contains(group.id) && !groups.contains(where: { $0.id == group.id }) {
            browser.removeTabGroup(group.id)
        }
    }
}
