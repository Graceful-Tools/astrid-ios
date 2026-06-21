import XCTest
@testable import Astrid_App

/// Tests for the atomic "Create Board" flow.
///
/// The old flow created a board in two requests — POST `/api/v1/projects`, then
/// PUT `/api/v1/lists/{id}` with the new `projectId`. If the second request
/// failed, an empty same-named orphan project was left behind (bug 2026-05-12).
///
/// The fix replaces that with a single atomic request to
/// `POST /api/v1/projects/from-list`, which creates the project AND attaches the
/// list in one server-side transaction — no orphan window. These tests lock the
/// request shape without touching the network.
final class AtomicCreateBoardTests: XCTestCase {

    func testFromListRequestCarriesListId() {
        let request = AstridAPIClient.makeCreateBoardFromListRequest(listId: "list-123")
        XCTAssertEqual(request.listId, "list-123",
                       "the atomic board request must carry the originating list id")
    }

    func testFromListRequestEncodesListIdToJSON() throws {
        let request = AstridAPIClient.makeCreateBoardFromListRequest(listId: "list-abc")
        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"listId\""), "encoded request must include listId key")
        XCTAssertTrue(json.contains("list-abc"), "encoded request must include the list id value")
    }
}
