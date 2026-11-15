import AstridCore
import CoreGraphics
import XCTest

/// AITD-679 / AITD-678: a board card's details open as a callout beside the card, on the side with
/// more room, through astrid-core's `calloutPlacement` rule. These are the eight cases of the
/// core-owned fixture `contracts/fixtures/callout-placement.json` (core ed8380c: the callout touches its anchor), table for table.
final class CalloutPlacementRulesTests: XCTestCase {

    private struct Case {
        let name: String
        let anchor: CGRect
        let size: CGSize
        let side: CalloutPlacement.Side
        let left: Double
        let top: Double
        let arrowOffset: Double
    }

    private let viewport = CGRect(x: 0, y: 0, width: 1400, height: 900)

    private let cases: [Case] = [
        Case(name: "side/room-on-the-right", anchor: CGRect(x: 40, y: 300, width: 320, height: 64),
             size: CGSize(width: 420, height: 520), side: .right, left: 360, top: 72, arrowOffset: 260),
        Case(name: "side/room-on-the-left", anchor: CGRect(x: 1000, y: 300, width: 320, height: 64),
             size: CGSize(width: 420, height: 520), side: .left, left: 580, top: 72, arrowOffset: 260),
        Case(name: "side/equal-room-opens-right", anchor: CGRect(x: 540, y: 300, width: 320, height: 64),
             size: CGSize(width: 420, height: 520), side: .right, left: 860, top: 72, arrowOffset: 260),
        Case(name: "arrow/points-at-the-rows-middle", anchor: CGRect(x: 40, y: 300, width: 320, height: 64),
             size: CGSize(width: 420, height: 520), side: .right, left: 360, top: 72, arrowOffset: 260),
        Case(name: "arrow/row-near-the-top-walks-the-arrow-up", anchor: CGRect(x: 40, y: 10, width: 320, height: 64),
             size: CGSize(width: 420, height: 520), side: .right, left: 360, top: 8, arrowOffset: 34),
        Case(name: "arrow/row-near-the-bottom-walks-it-down", anchor: CGRect(x: 40, y: 800, width: 320, height: 64),
             size: CGSize(width: 420, height: 520), side: .right, left: 360, top: 372, arrowOffset: 460),
        Case(name: "arrow/kept-off-the-near-corner", anchor: CGRect(x: 40, y: 0, width: 320, height: 24),
             size: CGSize(width: 420, height: 120), side: .right, left: 360, top: 8, arrowOffset: 20),
        Case(name: "arrow/kept-off-the-far-corner", anchor: CGRect(x: 40, y: 880, width: 320, height: 64),
             size: CGSize(width: 420, height: 120), side: .right, left: 360, top: 772, arrowOffset: 100),
    ]

    func testAITD679_everyFixtureCasePlacesLikeTheCore() throws {
        for c in cases {
            let placed = try CoreRules.calloutPlacement(anchor: c.anchor, viewport: viewport, size: c.size)
            XCTAssertEqual(placed.side, c.side, c.name)
            XCTAssertEqual(placed.left, c.left, accuracy: 0.001, c.name)
            XCTAssertEqual(placed.top, c.top, accuracy: 0.001, c.name)
            XCTAssertEqual(placed.width, Double(c.size.width), accuracy: 0.001, c.name)
            XCTAssertEqual(placed.height, Double(c.size.height), accuracy: 0.001, c.name)
            XCTAssertEqual(placed.arrowOffset, c.arrowOffset, accuracy: 0.001, c.name)
        }
    }
}
