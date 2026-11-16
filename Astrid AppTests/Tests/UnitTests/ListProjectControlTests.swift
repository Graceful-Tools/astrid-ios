//  ListProjectControlTests.swift
//  AITD-682: moving a list into and out of a project, and creating one inside it, on iPhone/iPad.
//  The controls are the ones the Mac draws (AITD-681), now shared from `Core/Lists`; these pin, in
//  the iOS target, that the offers are exactly the core's `listProjectMoves` answer (D68) and that
//  each action sends the right core command — against the pinned core, not a stub.

import AstridCore
import XCTest
@testable import Astrid_App

final class ListProjectControlTests: XCTestCase {

    private let projects = [Project(id: "a", name: "Alpha"), Project(id: "b", name: "Beta")]

    func testTheLongPressMenuOffersTheCoresDestinationsThenRemove_AITD682() {
        let moves = ListProjectMoves(canLeave: true, destinations: ["b", "a"], creatableIn: [])
        XCTAssertEqual(ListProjectControl.menuChoices(offered: true, moves: moves, projects: projects),
                       [.moveTo(projectId: "b", name: "Beta"), .moveTo(projectId: "a", name: "Alpha"),
                        .removeFromProject])
        // No choices keeps the row's old long-press (Favorite) — and Project Mode off offers none.
        XCTAssertEqual(ListProjectControl.menuChoices(offered: false, moves: moves, projects: projects), [])
        XCTAssertEqual(ListProjectControl.menuChoices(offered: true, moves: .none, projects: projects), [])
    }

    func testProjectModeIsOfferedOnlyWhenShippedAndFlagged_AITD682() {
        XCTAssertTrue(ListProjectControl.isOffered(deploymentShips: true, flagEnabled: true))
        XCTAssertFalse(ListProjectControl.isOffered(deploymentShips: true, flagEnabled: false))
        XCTAssertFalse(ListProjectControl.isOffered(deploymentShips: false, flagEnabled: true))
    }

    func testTheSettingsRowOffersNoneDestinationsAndNewProject_ReadOnlyWhenItMayNotLeave_AITD682() {
        let loose = TaskList(id: "l1", name: "Groceries")
        let picker = ListProjectControl.picker(
            list: loose, moves: ListProjectMoves(canLeave: false, destinations: ["a"], creatableIn: []),
            projects: projects, canEditSettings: true)
        XCTAssertEqual(picker.options, [.none, .project(id: "a", name: "Alpha"), .newProject])

        let stuck = ListProjectControl.picker(list: TaskList(id: "l2", name: "Ops", projectId: "b"),
                                              moves: .none, projects: projects, canEditSettings: true)
        XCTAssertTrue(stuck.readOnly)
        XCTAssertEqual(stuck.current, .project(id: "b", name: "Beta"))
        XCTAssertEqual(ListProjectControl.action(choosing: .none, current: stuck.current), .confirmLeave)
    }

    func testTheSidebarOffersNewListAndDropsOnlyWhereTheCoreAllows_AITD682() {
        let moves = ListProjectMoves(canLeave: false, destinations: ["a"], creatableIn: ["a"])
        XCTAssertTrue(ListProjectControl.offersNewList(in: "a", moves: moves))
        XCTAssertFalse(ListProjectControl.offersNewList(in: "b", moves: moves))
        XCTAssertTrue(ListProjectControl.acceptsDrop(of: TaskList(id: "l", name: "L"), onto: "a", moves: moves))
        XCTAssertFalse(ListProjectControl.acceptsDrop(of: TaskList(id: "l", name: "L"), onto: "b", moves: moves))
    }

    func testTheNewKeysExistInEnglish_AITD682() {
        for key in ["projects.project", "projects.none", "projects.new_project", "projects.move_to",
                    "projects.remove_from", "projects.new_list_in", "projects.new_list_in_title",
                    "projects.leave_confirm", "projects.leave_confirm_detail", "projects.move_forbidden",
                    "projects.create_forbidden", "project_mode.projects_heading", "mac.remove_favorite"] {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, key)
        }
    }

    /// The pinned core, seeded with a person, their projects and a loose list, takes each action's
    /// command as `ListService` builds it: the moves decode, a move lands, a null leaves, a list is
    /// born in a project, and a forbidden move comes back as the localized refusal.
    @MainActor func testEachActionSendsTheRightCoreCommand_AITD682() async throws {
        let session = try CoreSession(cachePath: ":memory:", baseURL: CoreSearchFixture.server,
                                      credentials: CoreSearchFixture.NoCredentials(), background: false)
        var seed = CoreCommand(kind: "seedCache")
        seed.set("currentUser", User(id: "me", email: "me@astrid.cc", name: "Me", image: nil))
        seed.set("lists", [TaskList(id: "loose", name: "Groceries", ownerId: "me")])
        seed.set("projects", [
            Project(id: "mine", name: "Alpha", ownerId: "me"),
            Project(id: "join", name: "Gamma", ownerId: "boss",
                    members: [ProjectMember(id: "m2", userId: "me", role: "member")]),
        ])
        struct Seeded: Decodable { let seeded: Bool }
        _ = try session.runBlocking(seed, as: Seeded.self)

        let moves = try await session.run(ListService.projectMovesCommand(listId: "loose"), as: ListProjectMoves.self)
        XCTAssertEqual(moves.destinations, ["mine"])
        XCTAssertEqual(ListProjectControl.menuChoices(offered: true, moves: moves, projects: [
            Project(id: "mine", name: "Alpha"), Project(id: "join", name: "Gamma"),
        ]), [.moveTo(projectId: "mine", name: "Alpha")])

        let moved = try await session.run(ListService.setListProjectCommand(listId: "loose", projectId: "mine"),
                                          as: TaskList.self)
        XCTAssertEqual(moved.projectId, "mine")
        let left = try await session.run(ListService.setListProjectCommand(listId: "loose", projectId: nil),
                                         as: TaskList.self)
        XCTAssertNil(left.projectId)

        let creatable = try await session.run(ListService.projectMovesCommand(listId: nil), as: ListProjectMoves.self)
        XCTAssertTrue(ListProjectControl.offersNewList(in: "join", moves: creatable),
                      "a project member may create a list in it")
        let born = try await session.run(ListService.createListCommand(name: "Q4", projectId: "join"),
                                         as: TaskList.self)
        XCTAssertEqual(born.projectId, "join")

        do {
            _ = try await session.run(ListService.setListProjectCommand(listId: "loose", projectId: "join"),
                                      as: TaskList.self)
            XCTFail("a plain project member may not move a list in")
        } catch {
            XCTAssertEqual(ListProjectControl.refusalKey(for: error), "projects.move_forbidden")
        }
    }

    // MARK: - ADEV-46: delete a project from its sidebar row (iPhone/iPad, and the Mac menu)

    func testDeleteIsOfferedOnlyToTheProjectsOwner_ADEV46() {
        let mine = Project(id: "p1", name: "Launch", ownerId: "me")
        XCTAssertTrue(ListProjectControl.offersDelete(of: mine, userId: "me", offered: true))
        // The server lets only the owner delete (DELETE /api/v1/projects/:id → 403 otherwise).
        XCTAssertFalse(ListProjectControl.offersDelete(of: mine, userId: "someone-else", offered: true))
        XCTAssertFalse(ListProjectControl.offersDelete(of: mine, userId: nil, offered: true))
        // Project Mode off draws no project menu at all.
        XCTAssertFalse(ListProjectControl.offersDelete(of: mine, userId: "me", offered: false))
    }

    func testAProjectWithNoKnownOwnerStillOffersDeleteAndTheServerDecides_ADEV46() {
        // A cached board without its owner must not lose the action; a refusal is then named.
        let unknown = Project(id: "p1", name: "Launch")
        XCTAssertTrue(ListProjectControl.offersDelete(of: unknown, userId: "me", offered: true))
    }

    func testTheServersOwnerOnlyDeleteRefusalIsNamed_ADEV46() {
        let forbidden = CoreFailure(kind: .refused, message: "Only the owner can delete", status: 403, id: nil)
        XCTAssertEqual(ListProjectControl.deleteRefusalKey(for: forbidden), "projects.delete_forbidden")
        let offline = CoreFailure(kind: .offline, message: "offline", status: nil, id: nil)
        XCTAssertNil(ListProjectControl.deleteRefusalKey(for: offline))
    }

    // MARK: - ADEV-47: a project is a sidebar section, not a level

    /// `SidebarProjectsSection`'s source, pinned as `SidebarPolishTests` pins the sidebar: a render
    /// needs the services and the session.
    private func sidebarSectionSource() throws -> String {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Lists/ListProjectViews.swift")
        let open = try XCTUnwrap(source.range(of: "struct SidebarProjectsSection"))
        return String(source[open.lowerBound...])
    }

    /// Jon: *"Project should be the same format as the current word 'Projects' or 'Lists' — it
    /// should not create another level of hierarchy. Project is like a custom favorites."* Each
    /// project is its own Section headed by its name, its lists the section's rows.
    func testEachProjectIsItsOwnSectionHeadedByItsName_ADEV47() throws {
        let source = try sidebarSectionSource()
        XCTAssertTrue(source.contains("Section {"), "one Section per project")
        XCTAssertTrue(source.contains("ForEach(entry.lists)"), "its lists are the section's own rows")
        XCTAssertFalse(source.contains("project_mode.projects_heading"),
                       "no umbrella Projects heading over the projects")
    }

    func testAProjectNoLongerExpandsOrIndentsItsLists_ADEV47() throws {
        let source = try sidebarSectionSource()
        XCTAssertFalse(source.contains("expanded"), "nothing to expand: the lists are always there")
        XCTAssertFalse(source.contains("chevron"), "no disclosure chevron")
        XCTAssertFalse(source.contains(".padding(.leading"), "lists are not indented under a row")
    }
}
