import SwiftUI

// Fork: tab trails, after Horse. A tab opened from a page, by a link or a
// script, hangs under the tab it came from in the column, indented a step for
// each page back; a page with a trail under it has a chevron that folds the
// trail away and opens it again.
//
// Only the order the column already has is read. Upstream puts a link's tab
// right after the page it came from (Browser.placeForLink), so a trail is a
// run of rows under its page. A tab is drawn under its page only while it is
// in that run; moved somewhere else, it stands on its own again. A closed
// page's trail moves up to the page before it, or out to the left.
//
// Kept for as long as the app is open: a relaunch brings the tabs back flat.
// The session file is upstream's, and is left as it is.

@MainActor
final class Trails: ObservableObject {
    static let shared = Trails()

    /// The tab each tab was opened from.
    private var parent: [Tab.ID: Tab.ID] = [:]
    /// Pages whose trail is folded away.
    @Published private(set) var folded: Set<Tab.ID> = []
    /// Bumped when a tab is noted, so the column draws it under its page.
    @Published private(set) var changes = 0

    /// How far a trail goes in before it stops stepping in.
    static let deepest = 4
    /// One step in.
    static let step: CGFloat = 12

    /// `tab` was opened from `source`.
    func note(_ tab: Tab.ID, from source: Tab.ID?) {
        guard let source, source != tab else { return }
        parent[tab] = source
        changes += 1
    }

    func toggle(_ tab: Tab.ID) {
        if folded.contains(tab) { folded.remove(tab) } else { folded.insert(tab) }
    }

    /// One row's place in its trail.
    struct Place: Equatable {
        var depth = 0
        /// Rows are under it, shown or folded.
        var leads = false
        var folded = false
        /// In a trail at all: a gutter is kept for the chevron.
        var trailed = false
    }

    /// The rows to draw, in order, and each one's place. Folded trails are
    /// left out, except the tab on screen, which is never hidden.
    func lay(_ rows: [Tab], active: Tab.ID?) -> (shown: [Tab], places: [Tab.ID: Place]) {
        let here = Set(rows.map(\.id))
        // The nearest page still among the rows that a tab came from, walking
        // past pages that have closed.
        func lead(of id: Tab.ID) -> Tab.ID? {
            var seen: Set<Tab.ID> = [id]
            var at = parent[id]
            while let up = at, !here.contains(up) {
                guard seen.insert(up).inserted else { return nil }
                at = parent[up]
            }
            return at
        }
        var places: [Tab.ID: Place] = [:]
        var stack: [Tab.ID] = []
        var shown: [Tab] = []
        for tab in rows {
            let up = lead(of: tab.id)
            while let top = stack.last, top != up { stack.removeLast() }
            var place = Place()
            if let up, stack.last == up {
                place.depth = min(stack.count, Trails.deepest)
                place.trailed = true
                places[up]?.leads = true
                places[up]?.trailed = true
            } else {
                stack = []
            }
            let hidden = stack.contains { folded.contains($0) } && tab.id != active
            stack.append(tab.id)
            place.folded = folded.contains(tab.id)
            places[tab.id] = place
            if !hidden { shown.append(tab) }
        }
        return (shown, places)
    }

    /// A position among the rows drawn, as a position among all of them, for
    /// a row carried to a new place while a trail is folded.
    static func index(_ at: Int, shown: [Tab], all: [Tab]) -> Int {
        guard !shown.isEmpty, shown.count != all.count else { return at }
        let at = min(max(at, 0), shown.count - 1)
        return all.firstIndex { $0.id == shown[at].id } ?? at
    }
}

/// A row stepped in for its place in its trail, with the chevron in the
/// gutter of a row that leads one.
struct TrailIndent: ViewModifier {
    let place: Trails.Place?
    let tab: Tab.ID
    @State private var hovering = false

    func body(content: Content) -> some View {
        if let place, place.trailed {
            HStack(spacing: 0) {
                Color.clear.frame(width: CGFloat(place.depth) * Trails.step)
                ZStack {
                    if place.leads {
                        Button { withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.18)) { Trails.shared.toggle(tab) } } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                                .rotationEffect(.degrees(place.folded ? 0 : 90))
                                .frame(width: Trails.step, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering = $0 }
                        .help(place.folded ? "Show the tabs opened from here" : "Fold away the tabs opened from here")
                    }
                }
                .frame(width: Trails.step)
                content
            }
        } else {
            content
        }
    }
}
