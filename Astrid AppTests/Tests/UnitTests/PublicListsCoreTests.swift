//  PublicListsCoreTests.swift
//  Public-list browsing and copying go through astrid-core (AITD-620, fifth slice): the commands
//  sent, and the core's catalogue row (`services/list.rs` `PublicListSummary`) read into the one
//  shared mapper (AITD-319).
//
//  The core's row is narrower than the old `/api/v1/public/lists` envelope: no `privacy` (every
//  row of the catalogue is public), no `createdAt`/`updatedAt`, no `admins`, and an owner without
//  a photo. None of those is drawn by a browse screen; the owner, which `role(for:)` consults, is
//  still carried.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests; what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

final class PublicListsCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// One row exactly as the core serializes `PublicListSummary` (camelCase, absent optionals).
    private func coreRow(owner: String? = #"{ "id": "owner-1", "name": "Sam", "email": "sam@example.com" }"#)
        throws -> PublicListData {
        let ownerField = owner.map { #", "owner": \#($0)"# } ?? ""
        let json = """
        {
          "id": "list-1",
          "name": "Trail Running",
          "description": "Routes worth the drive",
          "color": "#3b82f6",
          "imageUrl": "https://example.com/cover.png",
          "taskCount": 12,
          "memberCount": 3,
          "publicListType": "collaborative"\(ownerField)
        }
        """
        return try JSONDecoder().decode(PublicListData.self, from: Data(json.utf8))
    }

    // MARK: The commands

    func testTheCatalogueIsTheCoresPublicListsCommand_AITD620() throws {
        XCTAssertEqual(try json(PublicListCommands.catalogue())["kind"] as? String, "publicLists")
    }

    /// The core always copies with the tasks (`includeTasks: true`), as every caller asked for.
    func testCopyingNamesTheList_AITD620() throws {
        let sent = try json(PublicListCommands.copy(listId: "list-9"))
        XCTAssertEqual(sent["kind"] as? String, "copyList")
        XCTAssertEqual(sent["listId"] as? String, "list-9")
    }

    // MARK: The core's row

    func testTheCoresRowDecodesAndMaps_AITD620() throws {
        let list = TaskList(publicList: try coreRow())
        XCTAssertEqual(list.id, "list-1")
        XCTAssertEqual(list.name, "Trail Running")
        XCTAssertEqual(list.description, "Routes worth the drive")
        XCTAssertEqual(list.color, "#3b82f6")
        XCTAssertEqual(list.imageUrl, "https://example.com/cover.png")
        XCTAssertEqual(list.publicListType, "collaborative")
    }

    /// The core's row carries no `privacy`; a row of the public catalogue is public.
    func testARowWithoutPrivacyIsPublic_AITD620() throws {
        XCTAssertEqual(TaskList(publicList: try coreRow()).privacy, .PUBLIC)
    }

    /// The owner is what `role(for:)` consults (AITD-319); it survives the narrower row.
    func testTheOwnerSurvivesTheCoresRow_AITD620() throws {
        let list = TaskList(publicList: try coreRow())
        XCTAssertEqual(list.ownerId, "owner-1")
        XCTAssertEqual(list.owner?.name, "Sam")
        XCTAssertEqual(list.role(for: "owner-1"), .owner)
    }

    /// The core makes the owner optional; a row without one must still be shown, not dropped.
    func testARowWithoutAnOwnerStillDecodes_AITD620() throws {
        let list = TaskList(publicList: try coreRow(owner: nil))
        XCTAssertEqual(list.id, "list-1")
        XCTAssertNil(list.owner)
    }

    // MARK: A featured list's tasks (AITD-634)

    /// A featured list's tasks come from the core's `featuredRows`, not `getAllTasks(listId:)`;
    /// the list goes along, since this account usually does not hold it.
    func testAFeaturedListIsTheCoresFeaturedRowsCommand_AITD634() throws {
        let sent = try json(PublicListCommands.featuredRows(listId: "pub", list: TaskList(id: "pub", name: "Garden")))
        XCTAssertEqual(sent["kind"] as? String, "featuredRows")
        XCTAssertEqual(sent["listId"] as? String, "pub")
        XCTAssertEqual((sent["list"] as? [String: Any])?["id"] as? String, "pub")
    }

    func testAFeaturedListNotHeldSendsNoList_AITD634() throws {
        XCTAssertNil(try json(PublicListCommands.featuredRows(listId: "pub", list: nil))["list"])
    }

    /// The core answers the rows and, beside them, the tasks behind them whole — what the views
    /// draw and the detail view opens.
    func testTheFeaturedAnswerCarriesTheTasksWhole_AITD634() throws {
        let answer = """
        { "total": 1, "offset": 0, "matched": 1, "sortBy": "auto", "canAddTasks": false,
          "rows": [ { "id": "theirs", "title": "Plant tulips" } ],
          "tasks": [ { "id": "theirs", "title": "Plant tulips", "description": "In October",
                       "listIds": ["pub"], "creatorId": "them", "completed": false,
                       "priority": 0, "repeating": "never", "isAllDay": false, "isPrivate": false } ] }
        """
        let decoded = try CoreJSON.decoder.decode(PublicListCommands.FeaturedRowsAnswer.self, from: Data(answer.utf8))
        XCTAssertEqual(decoded.tasks.map(\.id), ["theirs"])
        XCTAssertEqual(decoded.tasks.first?.description, "In October")
    }
}
