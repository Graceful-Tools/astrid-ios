import AstridCore
import XCTest

/// AITD-680: moving a list into or out of a project, and creating one inside it, is decided by
/// astrid-core's `listProjectMoves` rule (D68). These are cases of the core-owned fixture
/// `contracts/fixtures/list-project-moves.json`, asked through the pinned binary, so the Mac
/// (AITD-681) and iOS (AITD-682) controls draw from the same answer web's server enforces.
final class ListProjectMovesRulesTests: XCTestCase {

    private struct Member: Encodable { let userId: String; let role: String }
    private struct Project: Encodable {
        let id: String
        let name: String
        let ownerId: String
        var members: [Member] = []
    }
    private struct List: Encodable {
        var id = "l1"
        var name = "Groceries"
        let ownerId: String
        var projectId: String?
        var listMembers: [Member] = []
        var listType: String?
    }
    private struct Request: Encodable {
        let kind = "listProjectMoves"
        var userId = "me"
        var list: List?
        var projects: [Project]
    }
    private struct Moves: Decodable, Equatable {
        let canLeave: Bool
        let destinations: [String]
        let creatableIn: [String]
    }

    private let projects = [
        Project(id: "mine", name: "Alpha", ownerId: "me"),
        Project(id: "run", name: "Beta", ownerId: "boss", members: [Member(userId: "me", role: "admin")]),
        Project(id: "join", name: "Gamma", ownerId: "boss", members: [Member(userId: "me", role: "member")]),
        Project(id: "look", name: "Delta", ownerId: "boss", members: [Member(userId: "me", role: "viewer")]),
        Project(id: "away", name: "Epsilon", ownerId: "boss"),
    ]

    private func ask(_ list: List?) throws -> Moves {
        try CoreRules.ask(Request(list: list, projects: projects), as: Moves.self)
    }

    func testAListOwnerMovesIntoProjectsTheyRunByName_AITD680() throws {
        XCTAssertEqual(
            try ask(List(ownerId: "me")),
            Moves(canLeave: false, destinations: ["mine", "run"], creatableIn: ["mine", "run", "join"]))
    }

    func testAPlainListMemberMovesNothing_AITD680() throws {
        let theirs = List(ownerId: "someone", listMembers: [Member(userId: "me", role: "member")])
        XCTAssertEqual(try ask(theirs).destinations, [])
    }

    func testLeavingNeedsAdminOfTheProjectLeft_AITD680() throws {
        XCTAssertEqual(
            try ask(List(ownerId: "me", projectId: "run")),
            Moves(canLeave: true, destinations: ["mine"], creatableIn: ["mine", "run", "join"]))
        let inJoin = try ask(List(ownerId: "me", projectId: "join"))
        XCTAssertFalse(inJoin.canLeave)
        XCTAssertEqual(inJoin.destinations, [])
    }

    func testAStatusListNeverMoves_AITD680() throws {
        let column = List(ownerId: "me", projectId: "mine", listType: "status")
        XCTAssertEqual(try ask(column).destinations, [])
        XCTAssertFalse(try ask(column).canLeave)
    }

    func testWithNoListOnlyWhereOneMayBeCreated_AITD680() throws {
        XCTAssertEqual(
            try ask(nil),
            Moves(canLeave: false, destinations: [], creatableIn: ["mine", "run", "join"]))
    }
}
