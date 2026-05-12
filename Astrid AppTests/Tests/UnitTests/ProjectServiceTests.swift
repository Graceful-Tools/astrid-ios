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
}
