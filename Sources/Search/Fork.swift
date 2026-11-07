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
}
