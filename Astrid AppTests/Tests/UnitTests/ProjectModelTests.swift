import XCTest
@testable import Astrid_App

/// Unit tests for `Project` + `ProjectMember` Codable conformance.
/// These pin the iOS-side shape against `V1Project` returned by
/// `/api/v1/projects` on the web. Any drift in field names should fail
/// here before iOS sees a runtime decode failure in production.
final class ProjectModelTests: XCTestCase {

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

    func testDecode_minimalProject() throws {
        let json = """
        {
          "id": "p1",
          "name": "My Board",
          "description": null,
          "color": "#3b82f6",
          "imageUrl": null,
          "ownerId": "u1",
          "owner": null,
          "members": [],
          "lists": [],
          "createdAt": "2026-05-11T00:00:00Z",
          "updatedAt": "2026-05-11T00:00:00Z"
        }
        """.data(using: .utf8)!

        let project = try decoder.decode(Project.self, from: json)
        XCTAssertEqual(project.id, "p1")
        XCTAssertEqual(project.name, "My Board")
        XCTAssertNil(project.description)
        XCTAssertEqual(project.color, "#3b82f6")
        XCTAssertEqual(project.ownerId, "u1")
        XCTAssertEqual(project.members?.count, 0)
        XCTAssertEqual(project.lists?.count, 0)
    }

    func testDecode_projectWithEmbeddedStatusLists() throws {
        let json = """
        {
          "id": "p1",
          "name": "Astrid Dev",
          "lists": [
            {
              "id": "l-ready",
              "name": "Ready",
              "projectId": "p1",
              "listType": "status",
              "statusRole": "ready",
              "statusOrder": 0,
              "statusDescription": "Time to get to work!",
              "statusCompleted": false,
              "recentlyCompletedWindow": null
            },
            {
              "id": "l-doing",
              "name": "Doing",
              "projectId": "p1",
              "listType": "status",
              "statusRole": "doing",
              "statusOrder": 1,
              "statusDescription": "Active work in progress!",
              "statusCompleted": false,
              "recentlyCompletedWindow": null
            }
          ]
        }
        """.data(using: .utf8)!

        let project = try decoder.decode(Project.self, from: json)
        XCTAssertEqual(project.lists?.count, 2)
        let ready = try XCTUnwrap(project.lists?.first { $0.statusRole == "ready" })
        XCTAssertEqual(ready.projectId, "p1")
        XCTAssertEqual(ready.listType, "status")
        XCTAssertEqual(ready.statusOrder, 0)
        XCTAssertEqual(ready.statusDescription, "Time to get to work!")
    }

    func testCodableRoundTrip_preservesAllFields() throws {
        let original = Project(
            id: "p1",
            name: "Project",
            description: "Test project",
            color: "#aabbcc",
            imageUrl: nil,
            ownerId: "u1",
            owner: nil,
            members: [],
            lists: [],
            createdAt: nil,
            updatedAt: nil
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Project.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testProjectMember_decode_fallsBackToUserIdWhenIdMissing() throws {
        let json = """
        {
          "userId": "u-42",
          "role": "admin"
        }
        """.data(using: .utf8)!

        let member = try decoder.decode(ProjectMember.self, from: json)
        XCTAssertEqual(member.userId, "u-42")
        XCTAssertEqual(member.role, "admin")
        XCTAssertEqual(member.id, "u-42", "id should fall back to userId when missing")
    }

    func testProjectMember_codableRoundTrip() throws {
        let original = ProjectMember(
            id: "m-1",
            projectId: "p-1",
            userId: "u-1",
            role: "admin",
            user: nil
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ProjectMember.self, from: data)
        XCTAssertEqual(decoded.userId, original.userId)
        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.projectId, original.projectId)
    }
}
