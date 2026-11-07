import XCTest
@testable import Search

/// Fork: spaces in the order they are dragged into, whichever profile they
/// belong to; a space the order hasn't seen keeps its place after the one
/// before it.
@MainActor
final class SpaceOrderTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "spaceorder-\(getpid())", 1)
        super.setUp()
    }

    private func space(_ name: String) -> Space {
        Space(id: UUID(), name: name, colour: 0)
    }

    func testDraggingASpaceOntoAnotherTakesItsPlace() {
        let order = SpaceOrder.shared
        let (a, b, c, d) = (space("a"), space("b"), space("c"), space("d"))
        let upstream = [a, b, c, d]
        order.move(d.id, onto: a.id, among: upstream)
        XCTAssertEqual(order.arrange(upstream).map(\.name), ["d", "a", "b", "c"])
        order.move(a.id, onto: c.id, among: order.arrange(upstream))
        XCTAssertEqual(order.arrange(upstream).map(\.name), ["d", "b", "c", "a"])
    }

    func testANewSpaceStaysAfterTheOneBeforeIt() {
        let order = SpaceOrder.shared
        let (a, b, c) = (space("a"), space("b"), space("c"))
        order.move(c.id, onto: a.id, among: [a, b, c])
        let fresh = space("new")
        XCTAssertEqual(order.arrange([a, fresh, b, c]).map(\.name), ["c", "a", "new", "b"])
    }

    func testAProfilesFirstSpaceCantBeDeleted() {
        XCTAssertFalse(SpaceOrder.deletable(Space.firstID))
        XCTAssertTrue(SpaceOrder.deletable(UUID()))
    }

    func testAnEmojiIsOneCharacterAndCanBeCleared() {
        let id = UUID()
        SpaceOrder.shared.setEmoji("🐎 horse", for: id)
        XCTAssertEqual(SpaceOrder.shared.emoji[id], "🐎")
        SpaceOrder.shared.setEmoji(nil, for: id)
        XCTAssertNil(SpaceOrder.shared.emoji[id])
    }
}
