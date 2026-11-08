import AppKit
import SwiftUI

// Fork: tabs into another space, several at once, as in Arc.
//
// - Move to Space, right-clicked on a tab among several picked with ⌘ or ⇧,
//   moves every picked tab, not only the one right-clicked.
// - A tab carried down the column and held over a space's icon in the row
//   at the column's foot: the column turns to that space, the tab still in
//   hand — and every tab picked with it — and they go wherever they are let
//   go among that space's tabs. Held over another icon, on to that space.
//   Let go over the icon itself, they go to the end of that space's tabs.
// - Several picked tabs carried along the column go together: they land
//   one after the other where the one in hand lands.
//
// Another profile's space takes them too, as in Arc: there the pages are
// opened afresh under that profile's sign-ins — a page never carries one
// profile's into another's (Profiles.swift) — and they close here. Pins
// stay where they are.

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
        moveToSpace(pickedOrOnly(tab), id, then: then)
    }

    func moveToSpace(_ moving: [Tab], _ id: UUID, then: (() -> Void)? = nil) {
        clearTabSelection()
        let from = spaceID
        TabUndo.moved(moving.map(\.id), from: from, to: id, in: self)
        var left = moving.count
        for each in moving {
            move(each, toSpace: id) {
                left -= 1
                if left == 0 { then?() }
            }
        }
    }

    /// The picked tabs carried with `tab`, after it has landed: one after
    /// the other just behind it, in its group or out of any as it is.
    func follow(_ tab: Tab) {
        let all = pickedOrOnly(tab)
        guard all.count > 1, tabs.contains(where: { $0.id == tab.id }) else { return }
        let others = all.filter { $0.id != tab.id && ($0.pin == nil) == (tab.pin == nil) }
        lay(others, after: tab)
    }

    /// `moving` put one after another right after `anchor`.
    func lay(_ moving: [Tab], after anchor: Tab) {
        let ids = Set(moving.map(\.id)).union([anchor.id])
        let partner = split(for: anchor)?.partner(of: anchor.id)
        guard let at = tabs.firstIndex(where: { $0.id == anchor.id }) else { return }
        let next = tabs.dropFirst(at + 1).first { !ids.contains($0.id) && $0.id != partner }
        if let next, next.groupID == anchor.groupID {
            for each in moving { dropTabIntoStrip(each, before: next) }
        } else if let group = anchor.groupID {
            var previous = anchor
            for each in moving {
                move(each, toGroup: GroupDropTarget(group: group, member: previous.id, after: true))
                previous = each
            }
        } else {
            for each in moving {
                if each.groupID != nil { move(each, toGroup: nil) }
                dropTabIntoStrip(each, before: next)
            }
        }
    }

    /// `moving` put one after another right before `anchor`.
    func lay(_ moving: [Tab], before anchor: Tab) {
        for each in moving where each.id != anchor.id {
            if anchor.groupID == nil, each.groupID != nil { move(each, toGroup: nil) }
            dropTabIntoStrip(each, before: anchor)
        }
    }
}

/// Where each space's icon is on screen, for a tab carried over one.
@MainActor
final class SpaceDrops: ObservableObject {
    static let shared = SpaceDrops()

    /// By window and space, in the window's own coordinates (SwiftUI's
    /// global: from the top left of the window's content). By window too:
    /// with profiles in one window, each profile's window draws the same
    /// row, and kept by space alone the one drawn last — tucked away, off
    /// screen — had every icon, and the window in front none.
    private var spots: [ObjectIdentifier: [UUID: CGRect]] = [:]
    /// The icon a tab is being carried over now.
    @Published private(set) var over: UUID?
    /// While several picked tabs are carried: the one in hand, and the
    /// others, lifted out of the column until they land behind it.
    @Published private(set) var lead: UUID?
    @Published private(set) var lifted: Set<UUID> = []
    private var release: Any?

    /// The picked tabs other than `tab` lifted, the first time a drag of
    /// it moves; put back at the button's release, however it ends.
    func lift(_ browser: Browser, carrying tab: Tab) {
        guard lead == nil else { return }
        let others = browser.pickedOrOnly(tab).filter { $0.id != tab.id }
        guard !others.isEmpty else { return }
        lead = tab.id
        withAnimation(Motion.quick) { lifted = Set(others.map(\.id)) }
        release = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            DispatchQueue.main.async { MainActor.assumeIsolated { SpaceDrops.shared.putDown() } }
            return event
        }
    }

    func putDown() {
        if let release { NSEvent.removeMonitor(release) }
        release = nil
        lead = nil
        withAnimation(Motion.quick) { lifted = [] }
    }
    /// Held over an icon this long, the column turns to its space.
    private static let dwell: TimeInterval = 0.3
    private var waiting: DispatchWorkItem?


    func place(_ space: UUID, at rect: CGRect, for browser: Browser) {
        spots[ObjectIdentifier(browser), default: [:]][space] = rect
    }

    /// The space of this window's profile whose icon is under the pointer.
    func space(under point: NSPoint, for browser: Browser) -> UUID? {
        guard let window = browser.window, let content = window.contentView else { return nil }
        let inWindow = window.convertPoint(fromScreen: point)
        let flipped = CGPoint(x: inWindow.x, y: content.bounds.height - inWindow.y)
        return spots[ObjectIdentifier(browser)]?.first { id, rect in
            rect.insetBy(dx: -2, dy: -4).contains(flipped)
                && id != browser.spaceID && browser.everySpace.contains { $0.id == id }
        }?.key
    }

    /// While a tab is carried: light the icon it is over, and held there,
    /// carry it into that space.
    func track(_ browser: Browser, carrying tab: Tab? = nil) {
        // Taken over by a carry into a space: the drag it came from goes on
        // telling where the pointer is until the button comes up, and would
        // carry its tab — gone from here — over again.
        guard !SpaceCarry.shared.active else { return }
        if let tab { lift(browser, carrying: tab) }
        let now = browser.prefs.usesSpaces ? space(under: NSEvent.mouseLocation, for: browser) : nil
        guard now != over else { return }
        guard let now, let tab else { return reset() }
        hold(browser, carrying: browser.pickedOrOnly(tab), over: now)
    }

    /// Over `space`'s icon with these in hand: held there long enough, on
    /// into that space with them.
    func hold(_ browser: Browser, carrying tabs: [Tab], over space: UUID) {
        over = space
        waiting?.cancel()
        let work = DispatchWorkItem { [weak self, weak browser] in
            guard let self, let browser, self.over == space,
                  NSEvent.pressedMouseButtons & 1 != 0 else { return }
            self.over = nil
            let here = tabs.filter { tab in browser.tabs.contains { $0 === tab } }
            guard !here.isEmpty else { return }
            SpaceCarry.shared.begin(here, in: browser, to: space)
        }
        waiting = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SpaceDrops.dwell, execute: work)
    }

    /// A tab let go: true when it was over a space's icon, and went to
    /// the end of that space with the others picked with it, the column
    /// following.
    func take(_ tab: Tab, in browser: Browser) -> Bool {
        defer {
            over = nil
            waiting?.cancel()
            waiting = nil
        }
        guard browser.prefs.usesSpaces, tab.pin == nil || !tab.everywhere,
              let id = space(under: NSEvent.mouseLocation, for: browser) else { return false }
        // After the drag has finished putting itself away.
        DispatchQueue.main.async {
            browser.carry(browser.pickedOrOnly(tab), to: id)
        }
        return true
    }

    func reset() {
        over = nil
        waiting?.cancel()
        waiting = nil
    }
}

/// Each row's place on screen in the column, for tabs carried into a space
/// to find where they are let go.
@MainActor
enum RowSpots {
    fileprivate static var spots: [UUID: (browser: ObjectIdentifier, rect: CGRect)] = [:]

    static func place(_ tab: UUID, at rect: CGRect, for browser: Browser) {
        spots[tab] = (ObjectIdentifier(browser), rect)
    }
}

struct RowSpot: ViewModifier {
    let browser: Browser
    let tab: Tab
    @ObservedObject private var drops = SpaceDrops.shared

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rect in
                RowSpots.place(tab.id, at: rect, for: browser)
            }
            // Several picked tabs carried: the others lifted out with the
            // one in hand, which says how many it carries.
            .opacity(drops.lifted.contains(tab.id) ? 0.25 : 1)
            .overlay(alignment: .trailing) {
                if drops.lead == tab.id, !drops.lifted.isEmpty {
                    Text("+\(drops.lifted.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.hover))
                        .padding(.trailing, 28)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Tabs carried into another space: in hand until the button comes up, a
/// little label of them under the pointer, landing in that space's column
/// where they are let go.
@MainActor
final class SpaceCarry {
    static let shared = SpaceCarry()

    private weak var browser: Browser?
    private var carried: [Tab] = []
    private var monitor: Any?
    private var label: NSPanel?
    /// The row they were last put beside, and which side: no move again
    /// until the pointer is somewhere else.
    private var lastSpot: (UUID, Bool)?

    var active: Bool { monitor != nil }

    func begin(_ tabs: [Tab], in browser: Browser, to space: UUID) {
        let moving = tabs.filter { !$0.bench && !($0.pin != nil && $0.everywhere) }
        guard !moving.isEmpty, space != browser.spaceID else { return }
        // The drag in the column puts itself down: its row is leaving.
        CarryGuard.endAll()
        self.browser = browser
        carried = moving
        lastSpot = nil
        if let across = browser.carry(moving, to: space) {
            // Another profile's: its window, with the pages opened afresh.
            self.browser = across.window
            carried = across.tabs
        }
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
                MainActor.assumeIsolated { SpaceCarry.shared.handle(event) }
                return event
            }
        }
        showLabel()
    }

    private func handle(_ event: NSEvent) {
        guard let browser else { return end() }
        moveLabel()
        if event.type == .leftMouseUp {
            if let space = SpaceDrops.shared.space(under: NSEvent.mouseLocation, for: browser) {
                // Let go over another icon: to the end of that space.
                let going = carried.filter { tab in browser.tabs.contains { $0 === tab } }
                browser.carry(going, to: space)
            } else {
                settle(in: browser)
            }
            SpaceDrops.shared.reset()
            return end()
        }
        // Over another icon: held there, on to that space.
        let now = SpaceDrops.shared.space(under: NSEvent.mouseLocation, for: browser)
        let here = carried.filter { tab in browser.tabs.contains { $0 === tab } }
        if let now, !here.isEmpty {
            if SpaceDrops.shared.over != now { SpaceDrops.shared.hold(browser, carrying: here, over: now) }
            return
        }
        SpaceDrops.shared.reset()
        settle(in: browser)
    }

    /// The carried tabs beside the row under the pointer.
    private func settle(in browser: Browser) {
        let here = carried.filter { tab in browser.tabs.contains { $0 === tab } }
        guard !here.isEmpty, let window = browser.window, let content = window.contentView else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: inWindow.x, y: content.bounds.height - inWindow.y)
        let ids = Set(here.map(\.id))
        let rows = browser.tabs.filter { !ids.contains($0.id) && ($0.pin == nil || $0.listed) }
        guard let (row, rect) = rows.compactMap({ tab -> (Tab, CGRect)? in
            guard let spot = RowSpots.spots[tab.id], spot.browser == ObjectIdentifier(browser) else { return nil }
            return (tab, spot.rect)
        }).first(where: { _, rect in
            rect.insetBy(dx: -20, dy: 0).contains(point)
        }) else { return }
        let after = point.y > rect.midY
        if let lastSpot, lastSpot.0 == row.id, lastSpot.1 == after { return }
        lastSpot = (row.id, after)
        let same = here.filter { ($0.pin == nil) == (row.pin == nil) }
        guard !same.isEmpty else { return }
        withAnimation(Motion.settle) {
            if after { browser.lay(same, after: row) } else { browser.lay(same, before: row) }
        }
    }

    private func end() {
        SpaceDrops.shared.putDown()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        label?.orderOut(nil)
        label = nil
        carried = []
        lastSpot = nil
    }

    // MARK: - the label under the pointer

    private func showLabel() {
        label?.orderOut(nil)
        guard let first = carried.first else { return }
        let more = carried.count - 1
        let view = NSHostingView(rootView: CarryLabel(title: first.label, more: more))
        view.frame.size = view.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.contentView = view
        label = panel
        moveLabel()
        panel.orderFront(nil)
    }

    private func moveLabel() {
        guard let label else { return }
        let at = NSEvent.mouseLocation
        label.setFrameOrigin(NSPoint(x: at.x + 12, y: at.y - label.frame.height - 8))
    }
}

private struct CarryLabel: View {
    let title: String
    let more: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
            if more > 0 {
                Text("+\(more)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(Palette.hover))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
        .fixedSize()
    }
}

extension Browser {
    /// Pressed on one of several picked tabs: nothing changes yet, so a
    /// drag starting from here carries them all. Making it the tab on
    /// screen would have dropped the pick (activeID's didSet clears it).
    /// Let go where it went down — a click — and it is that tab alone, as
    /// a click on a tab always was. False for any other press.
    func pressPicked(_ tab: Tab) -> Bool {
        guard selectedTabIDs.contains(tab.id), visibleSelectedTabCount > 1 else { return false }
        let start = NSEvent.mouseLocation
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            let end = NSEvent.mouseLocation
            if hypot(end.x - start.x, end.y - start.y) < 5 {
                DispatchQueue.main.async {
                    self?.clearTabSelection()
                    self?.select(tab)
                }
            }
            return event
        }
        return true
    }
}

extension Browser {
    /// `moving` into the space `id`, the column following: moved, in this
    /// profile; in another's, opened afresh in that profile's window at that
    /// space and closed here, pins left where they are. Nil within the
    /// profile; that window and the tabs opened there across.
    @discardableResult
    func carry(_ moving: [Tab], to id: UUID) -> (window: Browser, tabs: [Tab])? {
        guard id != spaceID else { return nil }
        if spaces.contains(where: { $0.id == id }) {
            moveToSpace(moving, id) { [weak self] in self?.switchSpace(to: id) }
            return nil
        }
        let going = moving.filter { $0.pin == nil && !$0.shy && !$0.bench && $0.address != nil }
        let pages = going.compactMap { $0.address }
        clearTabSelection()
        Browsers.join(space: id, from: self)
        guard let there = Browsers.front, there !== self, there.spaceID == id else { return nil }
        let opened = pages.map { there.open($0, foreground: false, atEnd: true) }
        if let first = opened.first { there.select(first) }
        for each in going { close(each) }
        return (there, opened)
    }
}
