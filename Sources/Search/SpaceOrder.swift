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
