import SwiftUI

// Fork: every space at the foot of the column, as Arc has them.
//
// Upstream draws one icon there, the space on screen, and a click opens the
// menu. Here each space has its icon in a row, the one on screen lit, and a
// click goes straight to it; with profiles in one window, every profile's
// spaces in the menu's order (Browser.everySpace). The one on screen, clicked
// again or right-clicked, opens the same menu the single icon did: rename,
// icon, order, downloads. The plus at the end makes a new space.
//
// Too many to fit at full size, and the icons get smaller; past that the
// row scrolls sideways, the space on screen kept in view.

struct SpaceRow: View {
    @ObservedObject var browser: Browser

    static let dot: CGFloat = 22
    /// As small as the icons go before the row scrolls instead.
    static let least: CGFloat = 16
    static let gap: CGFloat = 2

    /// Each icon's size for this many spaces, and the plus, in a column this
    /// wide: full size while they fit, smaller down to `least` after.
    static func size(_ count: Int, in width: CGFloat) -> CGFloat {
        let room = width - 20
        let each = room / CGFloat(count + 1) - gap
        return min(dot, max(least, each.rounded(.down)))
    }

    var body: some View {
        let spaces = browser.everySpace
        let size = SpaceRow.size(spaces.count, in: browser.prefs.sideWidth)
        let wide = CGFloat(spaces.count + 1) * (size + SpaceRow.gap) > browser.prefs.sideWidth - 20
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
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func icons(_ spaces: [Space], size: CGFloat) -> some View {
        HStack(spacing: SpaceRow.gap) {
            ForEach(spaces) { space in
                SpaceRowDot(browser: browser, space: space, here: space.id == browser.spaceID, size: size)
                    .id(space.id)
            }
            SpaceRowPlus(browser: browser, size: size)
        }
    }

    /// Whether the row is drawn, so the foot leaves out its single icon.
    @MainActor static func shows(_ browser: Browser) -> Bool {
        browser.prefs.usesSpaces && !browser.everySpace.isEmpty
    }
}

private struct SpaceRowDot: View {
    @ObservedObject var browser: Browser
    let space: Space
    let here: Bool
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        Button {
            if here { SpaceMenu.show(for: browser) } else { browser.switchSpace(to: space.id) }
        } label: {
            Image(systemName: space.symbol)
                .font(.system(size: here ? 12 : 10, weight: here ? .semibold : .medium))
                .foregroundStyle(here ? Palette.ink : (hovering ? Palette.ink : Palette.muted))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(here ? Palette.hover : (hovering ? Palette.hover.opacity(0.6) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Go to \(space.name)") { browser.switchSpace(to: space.id) }.disabled(here)
            Button("Space Options…") {
                if !here { browser.switchSpace(to: space.id) }
                DispatchQueue.main.async { SpaceMenu.show(for: browser) }
            }
        }
        .help(space.name)
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.15), value: here)
    }
}

private struct SpaceRowPlus: View {
    @ObservedObject var browser: Browser
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        Button { browser.askForSpace() } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Palette.hover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New Space")
    }
}
