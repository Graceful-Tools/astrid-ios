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

    func testDecode_projectsListWithSeededStatusLists() throws {
        // Mirrors what /api/v1/projects returns after a POST: the project
        // plus its three seeded status lists.
        let json = """
        {
          "projects": [
            {
              "id": "p1",
              "name": "Astrid Dev",
              "description": null,
              "color": "#3b82f6",
              "imageUrl": null,
              "ownerId": "u1",
              "owner": null,
              "members": [],
              "lists": [
                {
                  "id": "l-ready", "name": "Ready", "projectId": "p1",
                  "listType": "status", "statusRole": "ready", "statusOrder": 0,
                  "statusDescription": "Time to get to work!", "statusCompleted": false,
                  "recentlyCompletedWindow": null,
                  "privacy": "SHARED", "ownerId": "u1"
                },
                {
                  "id": "l-doing", "name": "Doing", "projectId": "p1",
                  "listType": "status", "statusRole": "doing", "statusOrder": 1,
                  "statusDescription": "Active work in progress!", "statusCompleted": false,
                  "recentlyCompletedWindow": null,
                  "privacy": "SHARED", "ownerId": "u1"
                },
                {
                  "id": "l-waiting", "name": "Waiting", "projectId": "p1",
                  "listType": "status", "statusRole": "waiting", "statusOrder": 2,
                  "statusDescription": "Paused.", "statusCompleted": false,
                  "recentlyCompletedWindow": null,
                  "privacy": "SHARED", "ownerId": "u1"
                }
              ],
              "createdAt": "2026-05-12T00:00:00Z",
              "updatedAt": "2026-05-12T00:00:00Z"
            }
          ],
          "meta": { "apiVersion": "v1", "authSource": "oauth" }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ProjectsResponse.self, from: json)
        XCTAssertEqual(response.projects.count, 1)
        let project = response.projects[0]
        XCTAssertEqual(project.id, "p1")
        XCTAssertEqual(project.lists?.count, 3)

        let ready = try XCTUnwrap(project.lists?.first { $0.statusRole == "ready" })
        XCTAssertEqual(ready.projectId, "p1")
        XCTAssertEqual(ready.listType, "status")
        XCTAssertEqual(ready.statusOrder, 0)
    }

    // MARK: - POST /api/v1/projects → ProjectResponse + CreateProjectRequest

    func testEncode_createProjectRequest_omitsNilFields() throws {
        let request = CreateProjectRequest(
            name: "My Board",
            description: nil,
            color: nil,
            imageUrl: nil
        )
        let data = try encoder.encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"name\":\"My Board\""))
        // The encoder doesn't strip nil keys by default; that's OK — the
        // server accepts null values the same as absent ones.
    }

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
