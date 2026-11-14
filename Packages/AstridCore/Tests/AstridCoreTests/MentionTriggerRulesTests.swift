import AstridCore
import XCTest

/// AITD-657 (AITD-655 / AITD-621): when a mention popup opens, through the rule door (core
/// `parse::mentions::find_trigger`), replacing iOS `detectAutocompleteTrigger` and Mac
/// `MacAutocomplete.detectTrigger`.
final class MentionTriggerRulesTests: XCTestCase {

    /// The divergence that held this up (AWTD2-199): core reached back past an invalid last `@`
    /// to an earlier one, so `"@jo@b"` opened `{mention, 0, "jo@b"}` where iOS opens nothing.
    func testAITD657_anInvalidLastSigilOpensNothing_matchingIOS() throws {
        XCTAssertNil(try CoreRules.mentionTrigger(text: "@jo@b"))
        XCTAssertEqual(try CoreRules.mentionTrigger(text: "hi @jo#x"),
                       MentionTrigger(kind: .mention, start: 3, query: "jo#x"),
                       "an invalid # settles # alone; the @ still answers")
    }

    func testAITD657_theClosestValidSigilWins() throws {
        XCTAssertEqual(try CoreRules.mentionTrigger(text: "@jon mentioned #car"),
                       MentionTrigger(kind: .list, start: 15, query: "car"))
        XCTAssertNil(try CoreRules.mentionTrigger(text: "email@test"))
        XCTAssertNil(try CoreRules.mentionTrigger(text: "@jon hello"))
        XCTAssertEqual(try CoreRules.mentionTrigger(text: "line one\n!bu")?.kind, .task)
    }

    /// `start` counts UTF-16 units, so an emoji before the sigil is two of them.
    func testAITD657_startIsUTF16_andMapsBackToAStringIndex() throws {
        let text = "🎉 #bu"
        let hit = try XCTUnwrap(CoreRules.mentionTrigger(text: text))
        XCTAssertEqual(hit.start, 3)
        XCTAssertEqual(hit.utf16Index(in: text).map { text[$0] }, "#")
    }
}
