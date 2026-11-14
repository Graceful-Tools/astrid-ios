import XCTest
@testable import Astrid_App

/// AITD-659 — a markdown table's columns: their own widths up to a cap, shrinking toward a floor
/// when room is short, and scrolling sideways only when even the floors do not fit.
final class MarkdownTableMetricsTests: XCTestCase {
    func testAITD659_aTableThatFitsKeepsItsColumnsOwnWidths() {
        XCTAssertEqual(MarkdownTableMetrics(natural: [60, 120], available: 400, spacing: 10).widths, [60, 120])
    }

    func testAITD659_longTextWrapsAtTheCapRatherThanStretchingTheColumn() {
        XCTAssertEqual(MarkdownTableMetrics(natural: [900, 40], available: nil, spacing: 10).widths,
                       [MarkdownTableMetrics.cap, 40])
    }

    /// Short of room, each column gives back in proportion to what it has above its floor; a
    /// column already narrower than the floor keeps its width.
    func testAITD659_shortOfRoomColumnsShrinkTowardTheirFloors() {
        let widths = MarkdownTableMetrics(natural: [200, 200, 40], available: 300, spacing: 10).widths
        XCTAssertEqual(widths.reduce(0, +) + 20, 300, accuracy: 0.001, "it fills the room exactly")
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.001)
        XCTAssertGreaterThan(widths[0], MarkdownTableMetrics.floor)
        XCTAssertEqual(widths[2], 40)
    }

    func testAITD659_whenEvenTheFloorsDoNotFitTheTableIsWiderThanItsRoom() {
        let natural: [CGFloat] = Array(repeating: 300, count: 6)
        let widths = MarkdownTableMetrics(natural: natural, available: 320, spacing: 10).widths
        XCTAssertEqual(widths, Array(repeating: MarkdownTableMetrics.floor, count: 6))
        XCTAssertGreaterThan(MarkdownTableMetrics.leastWidth(natural: natural, spacing: 10), 320, "so it scrolls")
    }
}
