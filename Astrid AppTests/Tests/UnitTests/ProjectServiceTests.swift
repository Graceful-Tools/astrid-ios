import XCTest
@testable import Astrid_App

/// Lightweight tests for `ProjectService` — focused on the parts that
/// don't require network mocking (cache hydration + `project(id:)`
/// lookup). Network-touching methods (`refreshFromServer`,
/// `createProject`, `deleteProject`) are covered indirectly by
/// `ProjectsAPIShapeTests` (DTO contract) and live integration testing
/// against the staging endpoint.
@MainActor
final class ProjectServiceTests: XCTestCase {

    /// `project(id:)` returns nil for an unknown id without throwing.
    func testProject_byId_returnsNil_whenAbsent() {
        let service = ProjectService.shared
        // Sanity: if Core Data is empty, this just returns nil.
        XCTAssertNil(service.project(id: "non-existent"))
    }

    /// Setting `projects` manually then `project(id:)` finds it.
    /// Documents the intended lookup contract for the board view.
    func testProject_byId_returnsMatch_whenPresent() {
        let service = ProjectService.shared
        let testProject = Project(id: "test-p1", name: "Test Project", ownerId: "u1")
        let original = service.projects
        service.projects = [testProject]
        defer { service.projects = original }

        XCTAssertEqual(service.project(id: "test-p1")?.id, "test-p1")
        XCTAssertEqual(service.project(id: "test-p1")?.name, "Test Project")
    }

    // MARK: - Attach-list payload (bug 2026-05-12 root cause)

    /// buildAttachListRequest constructs the PUT body that attaches a
    /// list to a newly-created project. Without this body field set,
    /// the originating list never picks up `projectId`, the board's
    /// `getProjectDomainTasks` filter returns zero tasks, and Inbox
    /// stays empty. This test pins the contract: the body MUST carry
    /// `projectId` so the list becomes the project's domain list.
    func testBuildAttachListRequest_carriesProjectId() throws {
        let body = ProjectService.buildAttachListRequest(projectId: "proj-42")
        XCTAssertEqual(body.projectId, "proj-42",
                       "Without projectId on the PUT body, tasks never appear in Inbox.")

        // Encode and confirm projectId actually serializes — encoder
        // strategies that omit nil keys must still include this one.
        let encoded = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"projectId\":\"proj-42\""),
                      "projectId must be serialized in the request body: \(json)")
    }
}
