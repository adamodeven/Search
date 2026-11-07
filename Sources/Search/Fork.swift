import Foundation

// What makes this build Adam's fork and not Office Commun's Search.
//
// Everything that differs from upstream about where updates come from and
// who signs them is here, so an upstream sync only ever conflicts on the
// few lines in Updater.swift that read these values.
//
// Releases are GitHub Releases on the fork (./release.sh makes them). The
// feed is the latest release's appcast; the ZIP and DMG it names are pinned
// to that release's tag. Everything is on github.com, which is what
// Updater.link requires (an address on the feed's own host).
//
// The updater only trusts builds signed with this Developer ID team, and a
// feed signed by it. An official Office Commun build is never offered here,
// and this fork's builds would never be accepted by an official one.
enum Fork {
    /// The GitHub repository releases are published to.
    static let repository = "adamodeven/Search"

    /// The Developer ID team that signs this fork's app, feed and AI engine.
    nonisolated static let team = "8KB3AN9HSZ"

    /// The feed: the plain appcast.json of the latest non-draft,
    /// non-prerelease release (the updater reads the signed .zip beside it).
    /// Intel Macs look for a name no release carries, so they are never
    /// offered an Apple Silicon build: release.sh publishes arm64 only.
    static var feed: URL {
        #if arch(x86_64)
        let name = "appcast-intel.json"
        #else
        let name = "appcast.json"
        #endif
        return URL(string: "https://github.com/\(repository)/releases/latest/download/\(name)")!
    }

    /// The default for switches this fork turns on that upstream leaves off:
    /// Profiles in one window, and Leave a new tab when the last tab closes.
    static let defaultOn = true
}

// MARK: - the window stays

@MainActor
extension Fork {
    /// ⌘W on a window's only tab, already blank: upstream closes the window.
    /// Here the window stays, its new tab with it, the field ready to type
    /// in. ⇧⌘W and the red button still close it.
    static func keepWindow(_ browser: Browser, blank: Tab) {
        browser.typed = ""
        blank.draft = ""
        browser.askFocus()
    }
}

// MARK: - what this fork leaves out

extension Fork {
    /// Bookmarks, as a whole: the bar, the button, the menu, the commands,
    /// the address field's suggestions from them, and bringing them in from
    /// another browser. Upstream's code is left as it is, so a sync with
    /// upstream doesn't conflict over it; nothing calls into it from here.
    /// The bookmarks file already on disk is left alone too.
    static let bookmarks = false

    /// Search's own password store, as a whole: its Passwords page, the offer
    /// to save a password after a sign-in, filling from it, and bringing
    /// passwords in from another browser. Sign-ins are filled from Apple's
    /// Passwords app instead (on unless switched off). Passwords already in
    /// the keychain under Search's name are left where they are.
    static let vault = false

    /// A command upstream lists that this fork leaves out: not in the menus,
    /// not in Settings › Shortcuts, and its key goes on to the page.
    static func hides(command id: String) -> Bool {
        (!bookmarks && id.hasPrefix("bookmarks.")) || (!vault && id == "app.passwords")
    }

    /// A row of Settings that this fork leaves out, on its page and in the
    /// find field.
    static func hides(setting id: String) -> Bool {
        (!bookmarks && id.hasPrefix("bookmarks.")) || (!vault && ["passwords.open", "passwords.save"].contains(id))
    }
}
