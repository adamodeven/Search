import SwiftUI
import UniformTypeIdentifiers

// Fork: every space at the foot of the column, as Arc has them.
//
// Upstream draws one icon there, the space on screen, and a click opens the
// menu. Here each space has its icon in a row, the one on screen lit, and a
// click goes straight to it; with profiles in one window, every profile's
// spaces, in the order they are dragged into (SpaceOrder.swift). An emoji
// can stand in for a space's symbol.
//
// Right-click a space for its own menu: go there, its emoji, its options
// (the one on screen), New Space…, and Delete — never for a profile's first
// space, which stays. Right-click the row anywhere else for New Space….
// Clicking the space on screen opens upstream's menu for it.
//
// Too many to fit at full size, and the icons get smaller; past that the
// row scrolls sideways, the space on screen kept in view.

struct SpaceRow: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var order = SpaceOrder.shared
    @State private var dragging: UUID?

    static let dot: CGFloat = 22
    /// As small as the icons go before the row scrolls instead.
    static let least: CGFloat = 16
    static let gap: CGFloat = 2
    /// All it takes up at the column's foot, its margin beneath included.
    static let height: CGFloat = dot + 4

    /// Each icon's size for this many spaces in a column this wide: full
    /// size while they fit, smaller down to `least` after.
    static func size(_ count: Int, in width: CGFloat) -> CGFloat {
        let room = width - 20
        let each = room / CGFloat(max(count, 1)) - gap
        return min(dot, max(least, each.rounded(.down)))
    }

    var body: some View {
        let spaces = browser.everySpace
        let size = SpaceRow.size(spaces.count, in: browser.prefs.sideWidth)
        let wide = CGFloat(spaces.count) * (size + SpaceRow.gap) > browser.prefs.sideWidth - 20
        Group {
            if wide {
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        icons(spaces, size: size)
                    }
                    .onAppear { reader.scrollTo(browser.spaceID, anchor: .center) }
                    .onChange(of: browser.spaceID) { _, id in
                        withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(id, anchor: .center) }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    icons(spaces, size: size)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: SpaceRow.dot)
        .contentShape(Rectangle())
        .contextMenu {
            Button("New Space…") { browser.askForSpace() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func icons(_ spaces: [Space], size: CGFloat) -> some View {
        HStack(spacing: SpaceRow.gap) {
            ForEach(spaces) { space in
                SpaceRowDot(browser: browser, space: space, here: space.id == browser.spaceID,
                            size: size, emoji: order.emoji[space.id], lifted: dragging == space.id)
                    .id(space.id)
                    .onDrag {
                        dragging = space.id
                        return NSItemProvider(object: space.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: SpaceDrop(target: space.id, dragging: $dragging) { moving in
                        withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.18)) {
                            order.move(moving, onto: space.id, among: browser.everySpace)
                        }
                    })
            }
        }
    }

    /// Whether the row is drawn, so the foot leaves out its single icon.
    @MainActor static func shows(_ browser: Browser) -> Bool {
        browser.prefs.usesSpaces && !browser.everySpace.isEmpty
    }
}

/// A space dragged over another takes its place as it goes, so the row
/// shows where it will land.
private struct SpaceDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID) -> Void

    func dropEntered(info: DropInfo) {
        if let dragging, dragging != target { move(dragging) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        SpaceOrder.shared.commit()
        return true
    }
}

private struct SpaceRowDot: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var drops = SpaceDrops.shared
    let space: Space
    let here: Bool
    let size: CGFloat
    let emoji: String?
    let lifted: Bool
    @State private var hovering = false

    /// A tab carried over it, to be let go here (TabsToSpace.swift).
    private var target: Bool { drops.over == space.id }

    var body: some View {
        Button {
            if here { SpaceMenu.show(for: browser) } else { browser.switchSpace(to: space.id) }
        } label: {
            Group {
                if let emoji {
                    Text(emoji)
                        .font(.system(size: here ? 14 : 12))
                        .opacity(here || hovering ? 1 : 0.75)
                } else {
                    Image(systemName: space.symbol)
                        .font(.system(size: here ? 12 : 10, weight: here ? .semibold : .medium))
                        .foregroundStyle(here || hovering ? Palette.ink : Palette.muted)
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(here ? Palette.hover : (hovering ? Palette.hover.opacity(0.6) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(target ? 0.6 : 0), lineWidth: 1.5)
            )
            .scaleEffect(target ? 1.15 : 1)
            .opacity(lifted ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rect in
            SpaceDrops.shared.place(space.id, at: rect, in: browser.window)
        }
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.12), value: target)
        .contextMenu { menu }
        .help(space.name)
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.15), value: here)
    }

    /// The menu for this space — the one right-clicked, whichever is on
    /// screen.
    @ViewBuilder
    private var menu: some View {
        if !here {
            Button("Go to “\(space.name)”") { browser.switchSpace(to: space.id) }
        } else {
            Button("Space Options…") { SpaceMenu.show(for: browser) }
        }
        Button("Choose Emoji…") {
            Ask.name("Emoji for “\(space.name)”", detail: "Press fn (🌐) for the emoji picker.",
                     placeholder: "😀", initial: emoji ?? "", confirm: "Use") {
                SpaceOrder.shared.setEmoji($0, for: space.id)
            }
        }
        if emoji != nil {
            Button("Use Its Symbol") { SpaceOrder.shared.setEmoji(nil, for: space.id) }
        }
        Divider()
        Button("New Space…") { browser.askForSpace() }
        if SpaceOrder.deletable(space.id) {
            Divider()
            Button("Delete “\(space.name)”…") { SpaceOrder.delete(space, from: browser) }
        }
    }
}
