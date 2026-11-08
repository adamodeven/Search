import AppKit
import XCTest
@testable import Search

/// Fork: a tab's menu and a drag act on every picked tab (ManyTabs.swift,
/// TabsToSpace.swift), and ⌘Z takes back what was done (TabUndo.swift).
@MainActor
final class ManyTabsTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "many-tabs-\(getpid())", 1)
        super.setUp()
    }

    private var made: [Browser] = []
    private var groupsWere = false

    override func tearDown() {
        // Nothing left for the next test: pins are kept on disk for the space.
        for browser in made {
            for tab in browser.tabs where tab.pin != nil { browser.unpin(tab) }
            for group in browser.tabGroups { browser.removeTabGroup(group.id) }
            for tab in browser.tabs { browser.close(tab) }
            browser.closeAll()
        }
        if let first = made.first { first.prefs.usesTabGroups = groupsWere }
        made = []
        super.tearDown()
    }

    private func makeBrowser() -> Browser {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        made.append(browser)
        groupsWere = browser.prefs.usesTabGroups
        browser.prefs.usesTabGroups = true
        let before = browser.tabs
        for word in ["one", "two", "three", "four"] {
            if browser.tabs.last?.isBlank == false { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "https://\(word).example/")!, title: word)
        }
        // Only these four, whatever an earlier test left in the space.
        let mine = Set(browser.tabs.suffix(4).map(\.id))
        for tab in before where !mine.contains(tab.id) {
            if tab.pin != nil { browser.unpin(tab) }
            browser.close(tab)
        }
        for group in browser.tabGroups { browser.removeTabGroup(group.id) }
        XCTAssertEqual(names(browser), ["one", "two", "three", "four"])
        return browser
    }

    private func names(_ browser: Browser) -> [String] { browser.tabs.map(\.label) }

    private func pick(_ browser: Browser, _ indices: [Int]) {
        browser.select(browser.tabs[indices[0]])
        for index in indices.dropFirst() { browser.extendTabSelection(to: browser.tabs[index], modifiers: .command) }
    }

    func testANewGroupTakesEveryPickedTabPinsToo() {
        let browser = makeBrowser()
        browser.pin(browser.tabs[0])
        pick(browser, [0, 2])
        let one = browser.tabs[0]
        browser.group(one, into: nil, new: true)
        XCTAssertEqual(browser.tabGroups.count, 1)
        let grouped = browser.tabs.filter { $0.groupID == browser.tabGroups[0].id }.map(\.label)
        XCTAssertEqual(Set(grouped), ["one", "three"])
        XCTAssertNil(one.pin)
    }

    func testPinActsOnEveryPickedTab() {
        let browser = makeBrowser()
        pick(browser, [1, 3])
        let two = browser.tabs[1]
        browser.pinMany(two)
        XCTAssertEqual(browser.tabs.filter { $0.pin != nil }.map(\.label), ["two", "four"])
    }

    func testRightClickedOutsideThePickedIsThatTabAlone() {
        let browser = makeBrowser()
        pick(browser, [0, 1])
        XCTAssertEqual(browser.many(browser.tabs[3]).map(\.label), ["four"])
        XCTAssertEqual(browser.many(browser.tabs[1]).map(\.label), ["one", "two"])
    }

    func testPickedTabsFollowTheOneCarried() {
        let browser = makeBrowser()
        pick(browser, [0, 1])
        let one = browser.tabs[0]
        browser.dropTabIntoStrip(one, before: nil)
        XCTAssertEqual(names(browser), ["two", "three", "four", "one"])
        browser.follow(one)
        XCTAssertEqual(names(browser), ["three", "four", "one", "two"])
    }

    func testUndoPutsAMoveBack() {
        let browser = makeBrowser()
        TabUndo.watch(browser)
        TabUndo.step(browser) { browser.dropTabIntoStrip(browser.tabs[0], before: nil) }
        XCTAssertEqual(names(browser), ["two", "three", "four", "one"])
        TabUndo.step(browser) { browser.pin(browser.tabs[1]) }
        XCTAssertEqual(browser.tabs[0].label, "three")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                   windowNumber: 0, context: nil, characters: "\u{1a}",
                                   charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        XCTAssertTrue(TabUndo.key(key, flags: .command, in: browser))
        XCTAssertNil(browser.tabs.first { $0.label == "three" }?.pin)
        XCTAssertTrue(TabUndo.key(key, flags: .command, in: browser))
        XCTAssertEqual(names(browser), ["one", "two", "three", "four"])
    }

    /// The closed list keeps a dozen: once full, a close still counts.
    func testUndoReopensACloseWithTheClosedListFull() {
        let browser = makeBrowser()
        for index in 0..<14 {
            browser.newTab()
            browser.tabs.last?.restore(url: URL(string: "https://filler\(index).example/")!, title: "filler")
            browser.close(browser.tabs.last!)
        }
        TabUndo.watch(browser)
        let two = browser.tabs[1]
        browser.close(two)
        XCTAssertEqual(names(browser), ["one", "three", "four"])
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                   windowNumber: 0, context: nil, characters: "\u{1a}",
                                   charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        let undone = expectation(description: "the close is seen")
        DispatchQueue.main.async {
            XCTAssertTrue(TabUndo.key(key, flags: .command, in: browser))
            XCTAssertEqual(browser.tabs.compactMap { $0.address?.host }, ["one.example", "two.example", "three.example", "four.example"])
            undone.fulfill()
        }
        wait(for: [undone], timeout: 2)
    }
}

/// Fork: a pin's name stays through ⌘W and a new window.
@MainActor
final class PinNameTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "pin-name-\(getpid())", 1)
        super.setUp()
    }

    func testARenamedPinKeepsItsNameWhenClosed() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.tabs.last?.restore(url: URL(string: "https://one.example/")!, title: "one")
        browser.newTab()
        browser.tabs.last?.restore(url: URL(string: "https://two.example/")!, title: "two")
        let tab = browser.tabs[0]
        browser.pin(tab)
        browser.select(tab)
        browser.beginTabRename(tab)
        browser.tabDraft = "Mine"
        browser.commitTabEdit()
        XCTAssertEqual(tab.name, "Mine")
        browser.close(tab)
        XCTAssertEqual(browser.tabs.first { $0.pin != nil }?.label, "Mine")
        let again = Browser(record: WindowRecord())
        XCTAssertEqual(again.tabs.first { $0.pin != nil }?.name, "Mine")
        again.closeAll()
        browser.closeAll()
    }
}

