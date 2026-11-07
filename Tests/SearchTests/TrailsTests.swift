import AppKit
import XCTest
@testable import Search

/// Fork: tab trails. A link's tab is drawn under the page it came from, a
/// step in for each page back, and a folded page hides its trail.
@MainActor
final class TrailsTests: XCTestCase {
    private var browser: Browser!

    override class func setUp() {
        setenv("SEARCH_PROBE", "trails-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        _ = NSApplication.shared
        browser = Browser(record: WindowRecord())
    }

    override func tearDown() {
        browser.closeAll()
        browser = nil
    }

    private func link(_ path: String, from source: Tab) -> Tab {
        browser.open(URL(string: "https://example.com/\(path)")!, foreground: false, from: source, link: true)
    }

    private var loose: [Tab] { browser.tabs.filter { $0.pin == nil } }

    func testLinksHangUnderThePageTheyCameFrom() {
        let root = browser.open(URL(string: "https://example.com/root")!, foreground: true)
        let child = link("child", from: root)
        let grandchild = link("grandchild", from: child)
        let (shown, places) = Trails.shared.lay(loose, active: root.id)

        XCTAssertEqual(places[root.id]?.depth, 0)
        XCTAssertEqual(places[root.id]?.leads, true)
        XCTAssertEqual(places[child.id]?.depth, 1)
        XCTAssertEqual(places[child.id]?.leads, true)
        XCTAssertEqual(places[grandchild.id]?.depth, 2)
        XCTAssertEqual(places[grandchild.id]?.leads, false)
        XCTAssertTrue(shown.contains { $0.id == grandchild.id })
    }

    func testFoldingAPageHidesItsTrailButNotTheTabOnScreen() {
        let root = browser.open(URL(string: "https://example.com/root")!, foreground: true)
        let child = link("child", from: root)
        let grandchild = link("grandchild", from: child)
        Trails.shared.toggle(root.id)
        defer { Trails.shared.toggle(root.id) }

        let folded = Trails.shared.lay(loose, active: root.id).shown.map(\.id)
        XCTAssertTrue(folded.contains(root.id))
        XCTAssertFalse(folded.contains(child.id))
        XCTAssertFalse(folded.contains(grandchild.id))

        let onScreen = Trails.shared.lay(loose, active: grandchild.id).shown.map(\.id)
        XCTAssertTrue(onScreen.contains(grandchild.id))
    }

    func testAClosedPagesTrailMovesUpToThePageBeforeIt() {
        let root = browser.open(URL(string: "https://example.com/root")!, foreground: true)
        let child = link("child", from: root)
        let grandchild = link("grandchild", from: child)
        browser.close(child)

        let places = Trails.shared.lay(loose, active: root.id).places
        XCTAssertEqual(places[grandchild.id]?.depth, 1)
    }

    func testAPlainNewTabIsNotInATrail() {
        let root = browser.open(URL(string: "https://example.com/root")!, foreground: true)
        _ = link("child", from: root)
        let plain = browser.open(URL(string: "https://example.com/plain")!, foreground: false, atEnd: true)

        let places = Trails.shared.lay(loose, active: root.id).places
        XCTAssertEqual(places[plain.id]?.trailed, false)
    }

    func testAPositionAmongShownRowsMapsToTheRealOne() {
        let all = (0..<4).map { _ in Tab(configuration: Web.configuration(space: browser.spaceID)) }
        let shown = [all[0], all[3]]
        XCTAssertEqual(Trails.index(1, shown: shown, all: all), 3)
        XCTAssertEqual(Trails.index(2, shown: all, all: all), 2)
    }
}
