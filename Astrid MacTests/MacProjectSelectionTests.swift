//  MacProjectSelectionTests.swift
//  The Projects sidebar section (AITD-674, web AWTD-1660): its selection tag, its gate, and which
//  lists each project section holds.

import XCTest
@testable import Astrid_Mac

final class MacProjectSelectionTests: XCTestCase {
    func testAProjectTagNeverReadsAsAListAndBack_AITD674() {
        let tag = MacProjectSelection.tag(projectId: "p1")
        XCTAssertEqual(MacProjectSelection.projectId(from: tag), "p1")
        XCTAssertNil(MacProjectSelection.projectId(from: "list-1"))
        XCTAssertNil(MacProjectSelection.projectId(from: nil))
        XCTAssertNil(MacProjectSelection.projectId(from: MacProjectSelection.prefix))
    }

    func testProjectsNeedBothTheDeploymentAndThePersonsFlag_AITD674() {
        XCTAssertTrue(MacProjectSelection.isOffered(deploymentShips: true, flagEnabled: true))
        XCTAssertFalse(MacProjectSelection.isOffered(deploymentShips: true, flagEnabled: false))
        XCTAssertFalse(MacProjectSelection.isOffered(deploymentShips: false, flagEnabled: true))
    }

    func testAProjectExpandsToItsOwnRealListsByName_AITD674_ADEV16() {
        let lists = [
            TaskList(id: "b", name: "Beta", projectId: "p"),
            TaskList(id: "a", name: "alpha", projectId: "p"),
            TaskList(id: "s", name: "Ready", projectId: "p", listType: "status"),
            TaskList(id: "v", name: "Smart", isVirtual: true, projectId: "p"),
            TaskList(id: "o", name: "Other", projectId: "q"),
        ]
        let projects = [Project(id: "q", name: "Zed"), Project(id: "p", name: "Alpha"), Project(id: "e", name: "Empty")]
        let entries = SidebarProjects.entries(offered: true, projects: projects, lists: lists)
        // The core's order (by name) and grouping, not the order the projects arrive in.
        XCTAssertEqual(entries.map(\.id), ["p", "e", "q"])
        XCTAssertEqual(entries[0].lists.map(\.id), ["a", "b"])
        XCTAssertEqual(entries[1].lists.map(\.id), [])
        XCTAssertEqual(entries[2].lists.map(\.id), ["o"])
    }

    func testNoProjectsSectionWhenProjectModeIsNotOffered_ADEV16() {
        let lists = [TaskList(id: "a", name: "A", projectId: "p")]
        XCTAssertTrue(SidebarProjects.entries(offered: false, projects: [Project(id: "p", name: "P")],
                                              lists: lists).isEmpty)
    }
}

// MARK: - ADEV-51: on the Mac too, a project is a sidebar section, not a level

final class MacProjectSidebarSectionsTests: XCTestCase {
    /// `MacProjectsSidebarSection`'s source, pinned as the iOS ADEV-47 tests pin theirs: a render
    /// needs the services and the session.
    private func sectionSource() throws -> String {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacProjectSelection.swift")
        let open = try XCTUnwrap(source.range(of: "struct MacProjectsSidebarSection"))
        return String(source[open.lowerBound...])
    }

    /// Jon: *"Project should be the same format as Projects or Lists — it should not create
    /// another level of hierarchy. Project is like a custom favorites."* Divergences follow iOS.
    func testEachProjectIsItsOwnSectionHeadedByItsName_ADEV51() throws {
        let source = try sectionSource()
        XCTAssertTrue(source.contains("ForEach(collapse.visibleLists(entry.lists"),
                      "its lists are the section's own rows (hidden only when folded, ADEV-57)")
        XCTAssertTrue(source.contains("header:"), "the project's name is the section header")
        XCTAssertFalse(source.contains("project_mode.projects_heading"),
                       "no umbrella Projects heading over the projects")
    }

    /// ADEV-51 said no second level; ADEV-57 then asked for the header to fold its section, which
    /// is not a level: the lists stay the section's own rows, never indented under a row.
    func testAProjectsListsAreNotIndentedUnderARow_ADEV51() throws {
        let source = try sectionSource()
        XCTAssertFalse(source.contains(".padding(.leading"), "lists are not indented under a row")
        XCTAssertFalse(source.contains("DisclosureGroup"), "a section that folds, not a disclosure row")
    }

    func testTheChevronSitsInTheListCountsColumn_ADEV77() throws {
        // Measured on Jon's screenshot (2x): the counts end 218.5pt in, the chevron ended 238pt in —
        // a section header runs 19.5pt closer to the sidebar's edge than a row's badge does.
        XCTAssertEqual(MacLayout.sidebarHeaderAccessoryTrailingInset, 19.5)
        let source = try sectionSource()
        XCTAssertTrue(source.contains(".padding(.trailing, MacLayout.sidebarHeaderAccessoryTrailingInset)"),
                      "the chevron is pulled in to the counts' column")
    }

    /// What the row carried moves onto the header: New Project stays (ADEV-27), and the header
    /// still opens the board, offers New List / Delete, and takes a dropped list.
    func testTheHeaderKeepsTheRowsActions_ADEV51() throws {
        let source = try sectionSource()
        for marker in ["sidebar.newProject", "sidebar.project.newList", "sidebar.project.delete",
                       "MacProjectSelection.tag(projectId:", ".dropDestination"] {
            XCTAssertTrue(source.contains(marker), "kept: \(marker)")
        }
        let root = try RepositoryLocator.source(at: "Astrid Mac/App/MacRootView.swift")
        XCTAssertFalse(root.contains("expandedProjectIds"), "the shell no longer tracks expansion")
    }
}
