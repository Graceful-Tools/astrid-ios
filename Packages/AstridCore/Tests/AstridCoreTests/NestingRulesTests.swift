import AstridCore
import XCTest

/// AITD-645 (core `b88ec47`, task 75a27f7f): identifiers and drag nesting through the rule door.
final class NestingRulesTests: XCTestCase {

    func testAITD645_anIdentifierParsesCaseInsensitivelyAndTrimmed() {
        XCTAssertEqual(CoreRules.identifierParse(" awtd-1007 "), CoreIdentifier(key: "AWTD", sequence: 1007))
    }

    /// `null` is an answer, not a failure — a title is a normal thing to type into a search box.
    func testAITD645_whatIsNotAnIdentifierIsNil() {
        for value in ["Buy milk", "A-1007", "AWTD-0", "#1007", "AWTD-1007a", "8cdcdbc9-37ef-45c0-8960-11ebb6287e01", ""] {
            XCTAssertNil(CoreRules.identifierParse(value), value)
        }
    }

    func testAITD645_formatUppercasesTheKey() throws {
        XCTAssertEqual(try CoreRules.identifierFormat(key: "awtd", sequence: 1007), "AWTD-1007")
    }

    private let rows = [
        NestingRow(id: "parent", parentTaskId: nil),
        NestingRow(id: "child", parentTaskId: "parent"),
        NestingRow(id: "grand", parentTaskId: "child"),
        NestingRow(id: "loose", parentTaskId: nil),
    ]

    func testAITD645_eachZoneAnswers() throws {
        XCTAssertEqual(try CoreRules.nesting(zone: .on("loose"), draggedId: "child", rows: rows),
                       .makeSubtask(parentId: "loose"))
        XCTAssertEqual(try CoreRules.nesting(zone: .on("grand"), draggedId: "parent", rows: rows), .none)
        XCTAssertEqual(try CoreRules.nesting(zone: .line, draggedId: "child", rows: rows), .moveToTopLevel)
        XCTAssertEqual(try CoreRules.nesting(zone: .line, draggedId: "loose", rows: rows), .reorderOnly)
        XCTAssertEqual(try CoreRules.nesting(zone: .outdent, draggedId: "grand", rows: rows),
                       .makeSubtask(parentId: "parent"))
        XCTAssertEqual(try CoreRules.nesting(zone: .indent(["parent", "loose"]), draggedId: "loose", rows: rows),
                       .makeSubtask(parentId: "parent"))
    }

    /// The outcome turns on the dragged row's own parent, so a row never sent is refused.
    func testAITD645_aDraggedRowThatWasNotSentIsRefused() {
        XCTAssertThrowsError(try CoreRules.nesting(zone: .line, draggedId: "ghost", rows: rows)) { error in
            XCTAssertEqual((error as? CoreFailure)?.kind, .badRequest)
        }
    }
}
