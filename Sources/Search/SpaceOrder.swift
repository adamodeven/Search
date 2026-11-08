import SwiftUI

// Fork: what this fork keeps about spaces beyond upstream's spaces.json.
//
// - An order across every profile: spaces dragged in the row at the foot
//   of the column go anywhere, whichever profile they belong to. Upstream
//   orders each profile's spaces on their own, profile after profile;
//   here that order is only the starting point. The row, ⌃1–⌃9 and the
//   space menu follow this one (Browser.everySpace). A two-finger swipe
//   still goes through a profile's own spaces as upstream has it.
// - Delete, from the row, for any space but a profile's first: that one
//   holds the profile's own sign-ins, and upstream keeps it. Its menu has
//   no Delete at all.
// - An emoji for a space, in place of its symbol, in the row.
//
// All in the app's settings, under fork.* keys; spaces.json is upstream's
// and is left as it is.

@MainActor
final class SpaceOrder: ObservableObject {
    static let shared = SpaceOrder()

    private let store = Store.settings
    private static let orderKey = "fork.spaces.order"
    private static let emojiKey = "fork.spaces.emoji"

    @Published private(set) var order: [UUID]
    @Published private(set) var emoji: [UUID: String]

    private init() {
        order = (store.stringArray(forKey: Self.orderKey) ?? []).compactMap(UUID.init)
        emoji = Dictionary(uniqueKeysWithValues: ((store.dictionary(forKey: Self.emojiKey) as? [String: String]) ?? [:])
            .compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
        DispatchQueue.main.async { SpaceOrder.shared.commit() }
    }

    /// Upstream's list, in this fork's order.
    func arrange(_ list: [Space]) -> [Space] {
        let place = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        // Spaces the order has never seen keep upstream's place among the
        // rest: each sorts just after the one before it.
        var last = -1.0
        let ranked: [(Double, Space)] = list.map { space in
            if let at = place[space.id] { last = Double(at); return (last, space) }
            last += 0.001
            return (last, space)
        }
        return ranked
            .enumerated()
            .sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }
            .map(\.element.1)
    }

    /// `moving` dropped on `target`: it takes `target`'s place, the rest
    /// moving along. `all` is every space as the row shows them.
    func move(_ moving: UUID, onto target: UUID, among all: [Space]) {
        var ids = all.map(\.id)
        guard moving != target, let from = ids.firstIndex(of: moving), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from)
        ids.insert(moving, at: to)
        order = ids + order.filter { !ids.contains($0) }
        store.set(order.map(\.uuidString), forKey: Self.orderKey)
    }

    /// Every profile's own list of spaces put in this order too, on disk,
    /// so a swipe and each window's list go the way the row does. Once a
    /// drag in the row is let go, and once at launch.
    func commit() {
        guard !order.isEmpty, !Store.testing else { return }
        let all = Spaces.read()
        let arranged = arrange(all)
        guard arranged.map(\.id) != all.map(\.id) else { return }
        store.set(true, forKey: "spaces.orderKept")
        Spaces.write(arranged)
    }

    func setEmoji(_ value: String?, for id: UUID) {
        if let first = value?.trimmingCharacters(in: .whitespacesAndNewlines).first {
            emoji[id] = String(first)
        } else {
            emoji[id] = nil
        }
        store.set(Dictionary(uniqueKeysWithValues: emoji.map { ($0.uuidString, $1) }), forKey: Self.emojiKey)
    }
}

// MARK: - deleting

@MainActor
extension SpaceOrder {
    /// Whether it can be deleted: not a profile's first space, the one
    /// that holds the profile's own sign-ins.
    static func deletable(_ id: UUID) -> Bool {
        id != Space.firstID && !Profiles.shared.list.contains { $0.home == id }
    }

    /// Delete, from the row's menu, for any space shown in it — another
    /// profile's too, with profiles in one window.
    static func delete(_ space: Space, from browser: Browser) {
        guard deletable(space.id) else { return }
        Ask.sure("Delete “\(space.name)”?",
                 detail: "Its tabs close, and its cookies and sign-ins are erased from this Mac. History stays.",
                 confirm: "Delete") {
            // Off it first, to the space before it in the row.
            if browser.spaceID == space.id {
                let all = browser.everySpace
                let at = all.firstIndex { $0.id == space.id } ?? 0
                let rest = all.filter { $0.id != space.id }
                if !rest.isEmpty { browser.switchSpace(to: rest[max(0, at - 1)].id) }
            }
            DispatchQueue.main.async {
                // The window of the space's own profile deletes it; another
                // profile's with no window yet gets one by going there.
                if let owner = Browsers.all.first(where: { $0.spaces.contains { $0.id == space.id } }) {
                    owner.deleteSpace(space.id)
                } else {
                    browser.switchSpace(to: space.id)
                    DispatchQueue.main.async {
                        Browsers.all.first { $0.spaces.contains { $0.id == space.id } }?.deleteSpace(space.id)
                    }
                }
            }
        }
    }
}

extension Browser {
    /// The space `step` along from the one on screen, in the row's order,
    /// whichever profile it is in; nil past either end.
    func spaceAlong(_ step: Int) -> Space? {
        let list = everySpace
        guard let at = list.firstIndex(where: { $0.id == spaceID }), list.indices.contains(at + step) else { return nil }
        return list[at + step]
    }

    /// A swipe's way past `target` (an index among this window's spaces):
    /// another profile's space, when that is what comes next in the row.
    func forkBeyond(_ target: Int) -> UUID? {
        guard !makingSpace, let here = spaces.firstIndex(where: { $0.id == spaceID }), target != here,
              let next = spaceAlong(target > here ? 1 : -1), next.profileID != profileID else { return nil }
        return next.id
    }

    /// Whether the page before is drawn beside during a swipe: a space of
    /// this window's own that comes before in the row.
    func drawsPage(before at: Int) -> Bool {
        guard at > 0 else { return false }
        if makingSpace { return true }
        return spaceAlong(-1).map { $0.profileID == profileID } ?? false
    }

    /// Nothing before this space in the row: a swipe back gives and returns.
    var firstInRow: Bool { !makingSpace && spaceAlong(-1) == nil }
}

@MainActor
enum SpaceSlide {
    /// A space of another profile clicked to: that profile's window, just
    /// put in this one's place, brings its rows in from the side the row
    /// says, as a swipe does.
    static func arrive(_ next: Browser, from current: Browser, to id: UUID) {
        guard !Motion.reduced, next !== current else { return }
        let list = current.everySpace
        guard let a = list.firstIndex(where: { $0.id == current.spaceID }),
              let b = list.firstIndex(where: { $0.id == id }), a != b else { return }
        let step = b > a ? 1 : -1
        let width = next.prefs.sidebar ? next.prefs.columnWidth : Metrics.strip
        next.spaceStep = step
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { next.spaceSwipe = CGFloat(step) * width }
        withAnimation(.easeOut(duration: 0.2)) { next.spaceSwipe = 0 }
    }
}
