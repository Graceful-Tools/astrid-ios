//  MacListProjectControlTests.swift
//  AITD-681: moving a list into and out of a project, and creating one inside it, on the Mac.
//  Every offer is the core's `listProjectMoves` answer (D68); these pin that the controls draw
//  exactly that answer and that each choice turns into the right core command.

#if os(macOS)
import AstridCore
import XCTest
@testable import Astrid_Mac

final class MacListProjectControlTests: XCTestCase {

    private let projects = [
        Project(id: "a", name: "Alpha"),
        Project(id: "b", name: "Beta"),
        Project(id: "g", name: "Gamma"),
    ]

    private func list(projectId: String? = nil) -> TaskList {
        TaskList(id: "l1", name: "Groceries", projectId: projectId)
    }

    // MARK: - The list menu

    func testTheMenuOffersExactlyTheCoresDestinationsInItsOrder_AITD681() {
        let moves = ListProjectMoves(canLeave: true, destinations: ["b", "a"], creatableIn: [])
        XCTAssertEqual(
            MacListProjectControl.menuChoices(offered: true, moves: moves, projects: projects),
            [.moveTo(projectId: "b", name: "Beta"), .moveTo(projectId: "a", name: "Alpha"), .removeFromProject])
    }

    func testTheMenuOffersNothingWithoutProjectMode_AITD681() {
        let moves = ListProjectMoves(canLeave: true, destinations: ["a"], creatableIn: ["a"])
        XCTAssertEqual(MacListProjectControl.menuChoices(offered: false, moves: moves, projects: projects), [])
    }

    func testRemoveIsOfferedOnlyWhenTheCoreSaysTheListMayLeave_AITD681() {
        let moves = ListProjectMoves(canLeave: false, destinations: ["a"], creatableIn: [])
        XCTAssertFalse(MacListProjectControl.menuChoices(offered: true, moves: moves, projects: projects)
            .contains(.removeFromProject))
    }

    func testADestinationWithNoCachedProjectIsNotDrawnAsABareId_AITD681() {
        let moves = ListProjectMoves(canLeave: false, destinations: ["gone", "a"], creatableIn: [])
        XCTAssertEqual(MacListProjectControl.menuChoices(offered: true, moves: moves, projects: projects),
                       [.moveTo(projectId: "a", name: "Alpha")])
    }

    // MARK: - List Settings ▸ Project

    func testALooseListOffersNoneTheDestinationsAndNewProject_AITD681() {
        let moves = ListProjectMoves(canLeave: false, destinations: ["a", "b"], creatableIn: [])
        let picker = MacListProjectControl.picker(list: list(), moves: moves, projects: projects,
                                                  canEditSettings: true)
        XCTAssertEqual(picker.current, .none)
        XCTAssertFalse(picker.readOnly)
        XCTAssertEqual(picker.options, [.none, .project(id: "a", name: "Alpha"),
                                        .project(id: "b", name: "Beta"), .newProject])
    }

    func testAListInAProjectItMayNotLeaveIsReadOnlyAndNamesIt_AITD681() {
        let picker = MacListProjectControl.picker(list: list(projectId: "g"), moves: .none,
                                                  projects: projects, canEditSettings: true)
        XCTAssertTrue(picker.readOnly)
        XCTAssertEqual(picker.current, .project(id: "g", name: "Gamma"))
        XCTAssertEqual(picker.options, [])
    }

    func testAListInAProjectOffersNoneItsProjectAndTheOthers_NoNewProject_AITD681() {
        let moves = ListProjectMoves(canLeave: true, destinations: ["a"], creatableIn: [])
        let picker = MacListProjectControl.picker(list: list(projectId: "b"), moves: moves,
                                                  projects: projects, canEditSettings: true)
        XCTAssertEqual(picker.options, [.none, .project(id: "b", name: "Beta"), .project(id: "a", name: "Alpha")])
    }

    func testNothingToOfferDrawsNoRow_AITD681() {
        let picker = MacListProjectControl.picker(list: list(), moves: .none, projects: projects,
                                                  canEditSettings: false)
        XCTAssertFalse(picker.readOnly)
        XCTAssertEqual(picker.options, [])
    }

    func testEachChoiceIsTheRightAction_AITD681() {
        let beta = MacListProjectControl.Option.project(id: "b", name: "Beta")
        XCTAssertEqual(MacListProjectControl.action(choosing: beta, current: .none), .move(projectId: "b"))
        XCTAssertEqual(MacListProjectControl.action(choosing: .none, current: beta), .confirmLeave)
        XCTAssertEqual(MacListProjectControl.action(choosing: .newProject, current: .none), .createProject)
        XCTAssertEqual(MacListProjectControl.action(choosing: beta, current: beta), .nothing)
    }

    // MARK: - Sidebar

    func testNewListInProjectFollowsCreatableIn_AITD681() {
        let moves = ListProjectMoves(canLeave: false, destinations: [], creatableIn: ["a"])
        XCTAssertTrue(MacListProjectControl.offersNewList(in: "a", moves: moves))
        XCTAssertFalse(MacListProjectControl.offersNewList(in: "b", moves: moves))
    }

    func testADropLandsOnlyWhereTheCoreAllows_AITD681() {
        let moves = ListProjectMoves(canLeave: true, destinations: ["a"], creatableIn: [])
        XCTAssertTrue(MacListProjectControl.acceptsDrop(of: list(projectId: "b"), onto: "a", moves: moves))
        XCTAssertFalse(MacListProjectControl.acceptsDrop(of: list(projectId: "b"), onto: "g", moves: moves))
        XCTAssertFalse(MacListProjectControl.acceptsDrop(of: list(projectId: "a"), onto: "a", moves: moves))
    }

    // MARK: - Refusals

    func testARefusalShowsItsLocalizedReason_AITD681() {
        func refusal(_ code: String?) -> Error {
            CoreFailure(kind: .refused, message: "no", status: 403, id: nil, code: code)
        }
        for code in ["LIST_PROJECT_MOVE_FORBIDDEN", "PROJECT_ATTACH_FORBIDDEN", "PROJECT_DETACH_FORBIDDEN"] {
            XCTAssertEqual(MacListProjectControl.refusalKey(for: refusal(code)), "projects.move_forbidden")
        }
        for code in ["LIST_PROJECT_CREATE_FORBIDDEN", "PROJECT_CREATE_FORBIDDEN"] {
            XCTAssertEqual(MacListProjectControl.refusalKey(for: refusal(code)), "projects.create_forbidden")
        }
        XCTAssertNil(MacListProjectControl.refusalKey(for: refusal(nil)))
        XCTAssertNotEqual(NSLocalizedString("projects.move_forbidden", comment: ""), "projects.move_forbidden")
    }

    // MARK: - The core commands

    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = try JSONEncoder().encode(command)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testMovingSendsSetListProject_AITD681() throws {
        let body = try json(ListService.setListProjectCommand(listId: "l1", projectId: "a"))
        XCTAssertEqual(body["kind"] as? String, "setListProject")
        XCTAssertEqual(body["listId"] as? String, "l1")
        XCTAssertEqual(body["projectId"] as? String, "a")
    }

    func testLeavingSendsAnExplicitNullProject_AITD681() throws {
        let body = try json(ListService.setListProjectCommand(listId: "l1", projectId: nil))
        XCTAssertEqual(body["kind"] as? String, "setListProject")
        XCTAssertTrue(body.keys.contains("projectId"), "absent would read as 'no change'")
        XCTAssertTrue(body["projectId"] is NSNull)
    }

    func testCreatingInAProjectSendsItOnTheCreate_AITD681() throws {
        let body = try json(ListService.createListCommand(name: "Q4", projectId: "a"))
        XCTAssertEqual(body["kind"] as? String, "createList")
        XCTAssertEqual(body["projectId"] as? String, "a")
        XCTAssertFalse(try json(ListService.createListCommand(name: "Loose")).keys.contains("projectId"))
    }

    func testAskingTheMovesNamesTheList_AITD681() throws {
        XCTAssertEqual(try json(ListService.projectMovesCommand(listId: "l1"))["listId"] as? String, "l1")
        let creating = try json(ListService.projectMovesCommand(listId: nil))
        XCTAssertEqual(creating["kind"] as? String, "listProjectMoves")
        XCTAssertFalse(creating.keys.contains("listId"))
    }

    // MARK: - Against the pinned core

    /// The real core, seeded with a signed-in person, two of their projects and one loose list,
    /// takes the commands exactly as `ListService` builds them: the moves decode, a move lands,
    /// and leaving with an explicit null takes it back out (offline — nothing is delivered).
    @MainActor func testThePinnedCoreTakesTheCommandsAsBuilt_AITD681() async throws {
        let session = try CoreSession(cachePath: ":memory:", baseURL: CoreSearchFixture.server,
                                      credentials: CoreSearchFixture.NoCredentials(), background: false)
        var seed = CoreCommand(kind: "seedCache")
        seed.set("currentUser", User(id: "me", email: "me@astrid.cc", name: "Me", image: nil))
        seed.set("lists", [TaskList(id: "loose", name: "Groceries", ownerId: "me")])
        seed.set("projects", [
            Project(id: "mine", name: "Alpha", ownerId: "me"),
            Project(id: "run", name: "Beta", ownerId: "boss",
                    members: [ProjectMember(id: "m1", userId: "me", role: "admin")]),
            Project(id: "join", name: "Gamma", ownerId: "boss",
                    members: [ProjectMember(id: "m2", userId: "me", role: "member")]),
        ])
        struct Seeded: Decodable { let seeded: Bool }
        _ = try session.runBlocking(seed, as: Seeded.self)

        let moves = try await session.run(ListService.projectMovesCommand(listId: "loose"),
                                          as: ListProjectMoves.self)
        XCTAssertEqual(moves, ListProjectMoves(canLeave: false, destinations: ["mine", "run"],
                                               creatableIn: ["mine", "run", "join"]))

        let moved = try await session.run(ListService.setListProjectCommand(listId: "loose", projectId: "run"),
                                          as: TaskList.self)
        XCTAssertEqual(moved.projectId, "run")
        let after = try await session.run(ListService.projectMovesCommand(listId: "loose"), as: ListProjectMoves.self)
        XCTAssertTrue(after.canLeave)

        let left = try await session.run(ListService.setListProjectCommand(listId: "loose", projectId: nil),
                                         as: TaskList.self)
        XCTAssertNil(left.projectId)

        do {
            _ = try await session.run(ListService.setListProjectCommand(listId: "loose", projectId: "join"),
                                      as: TaskList.self)
            XCTFail("a plain project member may not move a list in")
        } catch {
            XCTAssertEqual(MacListProjectControl.refusalKey(for: error), "projects.move_forbidden")
        }
    }
}
#endif
