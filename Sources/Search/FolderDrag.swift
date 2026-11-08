import SwiftUI

// Fork: a folder (a tab group in the column) picked up by its heading and
// carried up or down among the others, which make way as it passes, as a
// tab is carried. Upstream's way, a system drag let go exactly on another
// heading, is left out: there was nothing to show where it would go, and a
// heading between open folders was hard to hit.

@MainActor
enum FolderSpots {
    fileprivate static var spots: [UUID: CGRect] = [:]
}

struct FolderDrag: ViewModifier {
    @ObservedObject var browser: Browser
    let group: TabGroup
    @State private var held = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rect in
                FolderSpots.spots[group.id] = rect
            }
            .shadow(color: .black.opacity(held ? 0.14 : 0), radius: 10, y: 3)
            .zIndex(held ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { value in
                        held = true
                        move(to: value.location.y)
                    }
                    .onEnded { _ in held = false }
            )
    }

    /// Into the place of the folder whose stretch of the column — its
    /// heading down to the next one's — the pointer is in.
    private func move(to y: CGFloat) {
        let order = browser.tabGroups.map(\.id)
        guard let from = order.firstIndex(of: group.id) else { return }
        let tops = order.compactMap { id in FolderSpots.spots[id].map { (id, $0) } }
        guard tops.count == order.count else { return }
        var target = 0
        for (index, (_, rect)) in tops.enumerated() where y >= rect.minY {
            target = index
        }
        // Over its own stretch, or the heading just past it by less than half: stays.
        if target == from { return }
        if target > from, let rect = tops.dropFirst(target).first?.1, y < rect.midY { return }
        withAnimation(Motion.settle) { browser.moveTabGroup(group.id, to: target) }
    }
}

extension View {
    /// Upstream's system drag of a heading, unless folders are dragged by
    /// hand (Fork.folders).
    @ViewBuilder
    func upstreamGroupDrag(unless byHand: Bool, _ make: @escaping () -> NSItemProvider) -> some View {
        if byHand { self } else { onDrag(make) }
    }
}

/// FolderDrag where it applies: the column's headings.
struct FolderDragIn: ViewModifier {
    @ObservedObject var browser: Browser
    let group: TabGroup
    let on: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if on { content.modifier(FolderDrag(browser: browser, group: group)) } else { content }
    }
}
