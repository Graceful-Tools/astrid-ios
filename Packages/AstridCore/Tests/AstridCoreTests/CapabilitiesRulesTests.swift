import AstridCore
import XCTest

/// AITD-667: `TaskCapabilities`, `CommentVisibility.isSystem` and the Mac `FuzzyMatch` ask the
/// rule door (core `capabilities`, `commentVisibility`'s `isSystem`, `paletteRank`).
final class CapabilitiesRulesTests: XCTestCase {

    private struct List: Encodable {
        struct Supports: Encodable {
            var priority = true, dueDate = true, privateTasks = true
            var deleteTask = "delete"
        }
        let id: String
        var name = "List"
        var supports: Supports?
    }

    private let board = List(id: "board", supports: .init(priority: false, dueDate: false,
                                                          privateTasks: false,
                                                          deleteTask: "remove_from_list"))
    private let home = List(id: "home")

    func testAITD667_aBoardTheTaskIsOnRefusesItsControlsAndRemoves() {
        XCTAssertEqual(CoreRules.capabilities(listIds: ["board"], lists: [board, home]),
                       ListCapabilities(priority: false, dueDate: false, privateTasks: false,
                                        deletion: .removeFromList))
    }

    func testAITD667_alsoOnAClassicListTheDeleteDeletes() {
        XCTAssertEqual(CoreRules.capabilities(listIds: ["board", "home"], lists: [board, home]).deletion,
                       .delete)
    }

    func testAITD667_aListNotLoadedOrNotTheTasksRefusesNothing() {
        XCTAssertEqual(CoreRules.capabilities(listIds: ["home"], lists: [board, home]), .classic)
        XCTAssertEqual(CoreRules.capabilities(listIds: ["gone"], lists: [board]), .classic)
    }

    func testAITD667_aSystemCommentIsAuthorless_butNeverOffline() {
        XCTAssertTrue(CoreRules.isSystemComment(authorId: nil, remoteAuthorLogin: nil, offline: false))
        XCTAssertFalse(CoreRules.isSystemComment(authorId: nil, remoteAuthorLogin: nil, offline: true))
        XCTAssertFalse(CoreRules.isSystemComment(authorId: "u1", remoteAuthorLogin: nil, offline: false))
        XCTAssertFalse(CoreRules.isSystemComment(authorId: nil, remoteAuthorLogin: "octocat", offline: false),
                       "a GitHub commenter is a person (AITD-517)")
    }

    func testAITD667_paletteRankIsBestFirstWithTiesToTheShorterTitle() {
        XCTAssertEqual(CoreRules.paletteRank(query: "tdy",
                                             titles: ["Yesterday", "Today's plan", "Nothing", "Today"]),
                       [3, 1, 0])
        XCTAssertEqual(CoreRules.paletteRank(query: "new", titles: ["Renew Ticket", "New Task"]), [1, 0],
                       "a prefix outscores a match inside a word")
        XCTAssertEqual(CoreRules.paletteRank(query: "zzz", titles: ["New Task"]), [])
    }
}
