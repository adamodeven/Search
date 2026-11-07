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
// Too many to fit, and the row gives way to upstream's single icon.

struct SpaceRow: View {
    @ObservedObject var browser: Browser

    static let dot: CGFloat = 22
    static let gap: CGFloat = 2

    /// Room for every space and the plus, in a column this wide.
    static func fits(_ count: Int, in width: CGFloat) -> Bool {
        CGFloat(count + 1) * (dot + gap) <= width - 20
    }

    var body: some View {
        let spaces = browser.everySpace
        if spaces.count > 1, SpaceRow.fits(spaces.count, in: browser.prefs.sideWidth) {
            HStack(spacing: SpaceRow.gap) {
                Spacer(minLength: 0)
                ForEach(spaces) { space in
                    SpaceRowDot(browser: browser, space: space, here: space.id == browser.spaceID)
                }
                SpaceRowPlus(browser: browser)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
    }

    /// Whether the row is drawn, so the foot leaves out its single icon.
    @MainActor static func shows(_ browser: Browser) -> Bool {
        browser.prefs.usesSpaces && browser.everySpace.count > 1
            && fits(browser.everySpace.count, in: browser.prefs.sideWidth)
    }
}

private struct SpaceRowDot: View {
    @ObservedObject var browser: Browser
    let space: Space
    let here: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            if here { SpaceMenu.show(for: browser) } else { browser.switchSpace(to: space.id) }
        } label: {
            Image(systemName: space.symbol)
                .font(.system(size: here ? 12 : 10, weight: here ? .semibold : .medium))
                .foregroundStyle(here ? Palette.ink : (hovering ? Palette.ink : Palette.muted))
                .frame(width: SpaceRow.dot, height: SpaceRow.dot)
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
    @State private var hovering = false

    var body: some View {
        Button { browser.askForSpace() } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .frame(width: SpaceRow.dot, height: SpaceRow.dot)
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
