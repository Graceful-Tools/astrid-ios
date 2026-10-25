import XCTest
@testable import Astrid_App

/// Pure Codable tests for the project DTOs against the same JSON
/// shapes /api/v1/projects emits on astrid-web. No network calls — we
/// decode/encode against canned strings so the contract is enforced
/// without simulator-side networking flakes.
///
/// Web counterpart: tests/api/v1-projects.test.ts and v1-contract.test.ts.
final class ProjectsAPIShapeTests: XCTestCase {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: - GET /api/v1/projects → ProjectsResponse

    func testDecode_emptyProjectsList() throws {
        let json = """
        { "projects": [], "meta": { "apiVersion": "v1", "authSource": "oauth" } }
        """.data(using: .utf8)!
        let response = try decoder.decode(ProjectsResponse.self, from: json)
        XCTAssertEqual(response.projects.count, 0)
    }

    // MARK: - POST /api/v1/projects → ProjectResponse + CreateProjectRequest

    func testDecode_projectResponseWrapper() throws {
        let json = """
        {
          "project": { "id": "p1", "name": "X" },
          "meta": { "apiVersion": "v1", "authSource": "oauth" }
        }
        """.data(using: .utf8)!
        let response = try decoder.decode(ProjectResponse.self, from: json)
        XCTAssertEqual(response.project.id, "p1")
        XCTAssertEqual(response.project.name, "X")
    }

    // MARK: - DELETE /api/v1/projects/:id → DeleteProjectResponse

    func testDecode_deleteProjectResponse() throws {
        let json = """
        {
          "success": true,
          "detachedListIds": ["domain-list-1", "domain-list-2"],
          "meta": { "apiVersion": "v1", "authSource": "oauth" }
        }
        """.data(using: .utf8)!
        let response = try decoder.decode(DeleteProjectResponse.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.detachedListIds, ["domain-list-1", "domain-list-2"])
    }

    func testDecode_deleteProjectResponse_emptyDetachedIds() throws {
        let json = """
        { "success": true, "detachedListIds": [], "meta": { "apiVersion": "v1", "authSource": "oauth" } }
        """.data(using: .utf8)!
        let response = try decoder.decode(DeleteProjectResponse.self, from: json)
        XCTAssertEqual(response.detachedListIds, [])
    }

    // MARK: - PUT /api/v1/lists/:id round-trips recentlyCompletedWindow

    func testEncode_updateListRequest_withRecentlyCompletedWindow() throws {
        var update = UpdateListRequest()
        update.recentlyCompletedWindow = .duration(amount: 7, unit: .day)
        let data = try encoder.encode(update)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"recentlyCompletedWindow\""))
        XCTAssertTrue(json.contains("\"kind\":\"duration\""))
        XCTAssertTrue(json.contains("\"amount\":7"))
        XCTAssertTrue(json.contains("\"unit\":\"day\""))
    }

    func testEncode_updateListRequest_withSinceDate() throws {
        var update = UpdateListRequest()
        update.recentlyCompletedWindow = .sinceDate(date: "2026-04-01")
        let data = try encoder.encode(update)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"since-date\""))
        XCTAssertTrue(json.contains("\"date\":\"2026-04-01\""))
    }
}
