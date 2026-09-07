//  PublicListMappingTests.swift
//  One mapper from PublicListData to TaskList — task 698717b9 (AITD-319).
//
//  This conversion was hand-written three times: verbatim in ListSidebarView and
//  PublicListBrowserView, and a third, shorter time in MacRootView. The Mac copy dropped `owner`,
//  `createdAt` and `description`.
//
//  The missing `owner` is the one that matters. `TaskList.role(for:)` consults `owner?.id`
//  alongside `ownerId`, so a public list opened on the Mac was answering the permission question
//  with less information than the same list opened on iOS. Two mappers, two different lists.

import XCTest
@testable import Astrid_App

final class PublicListMappingTests: XCTestCase {

    private func publicListData(privacy: String = "PUBLIC") throws -> PublicListData {
        let json = """
        {
          "id": "list-1",
          "name": "Trail Running",
          "description": "Routes worth the drive",
          "color": "#3b82f6",
          "privacy": "\(privacy)",
          "publicListType": "collaborative",
          "imageUrl": "https://example.com/cover.png",
          "createdAt": "2026-01-02T03:04:05Z",
          "updatedAt": "2026-02-03T04:05:06Z",
          "owner": {
            "id": "owner-1",
            "name": "Sam",
            "email": "sam@example.com",
            "image": "https://example.com/sam.png"
          },
          "admins": [],
          "taskCount": 12,
          "memberCount": 3
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PublicListData.self, from: Data(json.utf8))
    }

    func testTheOwnerSurvivesTheMapping() throws {
        let list = TaskList(publicList: try publicListData())

        XCTAssertEqual(list.ownerId, "owner-1")
        XCTAssertEqual(list.owner?.id, "owner-1",
                       "role(for:) consults owner?.id — dropping it makes the Mac answer the "
                       + "permission question differently from iOS")
        XCTAssertEqual(list.owner?.name, "Sam")
        XCTAssertEqual(list.owner?.email, "sam@example.com")
    }

    func testTheOwnerIsRecognisedAsTheOwner() throws {
        // The consequence, stated directly rather than left to be inferred from the field above.
        let list = TaskList(publicList: try publicListData())
        XCTAssertEqual(list.role(for: "owner-1"), .owner)
    }

    func testTheFieldsTheMacCopyDroppedAreAllCarried() throws {
        let list = TaskList(publicList: try publicListData())

        XCTAssertEqual(list.description, "Routes worth the drive")
        XCTAssertNotNil(list.createdAt)
        XCTAssertNotNil(list.updatedAt)
    }

    func testTheOrdinaryFieldsAreCarried() throws {
        let list = TaskList(publicList: try publicListData())

        XCTAssertEqual(list.id, "list-1")
        XCTAssertEqual(list.name, "Trail Running")
        XCTAssertEqual(list.color, "#3b82f6")
        XCTAssertEqual(list.imageUrl, "https://example.com/cover.png")
        XCTAssertEqual(list.publicListType, "collaborative")
    }

    func testPrivacyIsReadFromThePayloadRatherThanAssumed() throws {
        // A browse endpoint returning a non-public row must not be forced to PUBLIC — the Mac copy
        // hardcoded `.PUBLIC`, which would have mislabelled it.
        XCTAssertEqual(TaskList(publicList: try publicListData(privacy: "PUBLIC")).privacy, .PUBLIC)
        XCTAssertEqual(TaskList(publicList: try publicListData(privacy: "PRIVATE")).privacy, .PRIVATE)
    }

    /// The guard: nobody writes a fourth copy.
    func testNoSurfaceHandRollsTheMappingAgain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        let audited = [
            "Astrid App/Views/Lists/ListSidebarView.swift",
            "Astrid App/Views/Lists/PublicListBrowserView.swift",
            "Astrid Mac/App/MacRootView.swift",
        ]

        for relative in audited {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertFalse(source.contains("listData.owner.id") || source.contains("data.owner.id"),
                           "\(relative) builds a TaskList from a public list by hand — "
                           + "use TaskList(publicList:) (AITD-319)")
        }
    }
}
