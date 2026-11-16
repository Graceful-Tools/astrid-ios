import AstridCore
import XCTest

/// ADEV-16: the sidebar's Projects section is astrid-core's `sidebar` rule (core `886817e`,
/// AWTD-1681, D70), not a Swift grouping. Cases from the core-owned fixture
/// `contracts/fixtures/sidebar-projects.json`, asked through the pinned binary.
final class SidebarProjectsRulesTests: XCTestCase {

    private let lists = [
        SidebarListInput(id: "web", name: "Web", projectId: "astrid", listType: nil),
        SidebarListInput(id: "api", name: "api", projectId: "astrid", listType: nil),
        SidebarListInput(id: "starred", name: "Roadmap", projectId: "astrid", listType: nil),
        SidebarListInput(id: "doing", name: "Doing", projectId: "astrid", listType: "status"),
        SidebarListInput(id: "bug", name: "Bug", projectId: "astrid", listType: "label"),
        SidebarListInput(id: "garden", name: "Garden", projectId: "home", listType: nil),
        SidebarListInput(id: "secret", name: "Elsewhere", projectId: "unseen", listType: nil),
        SidebarListInput(id: "groceries", name: "Groceries", projectId: nil, listType: nil),
    ]

    private let projects = [
        SidebarProjectInput(id: "home", name: "home", key: nil, color: "#22c55e"),
        SidebarProjectInput(id: "astrid", name: "Astrid", key: nil, color: "#ef4444"),
        SidebarProjectInput(id: "empty", name: "Someday", key: nil, color: nil),
        SidebarProjectInput(id: "keyed", name: "", key: "MOB", color: nil),
    ]

    func testNoSectionWithoutProjectMode_ADEV16() {
        XCTAssertNil(CoreRules.sidebarProjects(lists: lists, projects: nil))
    }

    func testNoSectionWhenTheReaderSeesNoProjects_ADEV16() {
        XCTAssertNil(CoreRules.sidebarProjects(lists: lists, projects: []))
    }

    func testEveryProjectByNameWithItsOwnDomainListsByName_ADEV16() throws {
        let rows = try XCTUnwrap(CoreRules.sidebarProjects(lists: lists, projects: projects))
        // By name, case folded; an empty name falls back to the key. A project with no lists is
        // still a row. Columns and labels are not places; a list naming an unseen project is in
        // no project.
        XCTAssertEqual(rows.map(\.id), ["astrid", "home", "keyed", "empty"])
        XCTAssertEqual(rows.map(\.name), ["Astrid", "home", "MOB", "Someday"])
        XCTAssertEqual(rows[0].listIds, ["api", "starred", "web"])
        XCTAssertEqual(rows[1].listIds, ["garden"])
        XCTAssertEqual(rows[2].listIds, [])
        XCTAssertEqual(rows[0].color, "#ef4444")
    }
}
