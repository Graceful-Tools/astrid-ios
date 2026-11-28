//  ProjectsSettingsTests.swift
//  ADEV-357 (Jon, 2026-11-27): "Remove New project from the side-bar and add to settings … add /
//  edit should also be in a separate settings tab on mac, web, ios." Settings ▸ Projects lists
//  the projects, makes one, and opens Edit Project… for whoever the server lets edit it.

import XCTest
@testable import Astrid_App

final class ProjectsSettingsTests: XCTestCase {

    private let projects = [
        Project(id: "p2", name: "zebra", ownerId: "me"),
        Project(id: "p1", name: "Apple", color: "#ff0000", ownerId: "someone",
                members: [ProjectMember(id: "m1", projectId: "p1", userId: "me", role: "admin")]),
        Project(id: "p3", name: "Mango", ownerId: "someone",
                members: [ProjectMember(id: "m2", projectId: "p3", userId: "me", role: "member")]),
    ]

    func testADEV357_theTabShowsOnlyWithProjectMode() {
        XCTAssertTrue(ProjectsSettings.isShown(offered: true))
        XCTAssertFalse(ProjectsSettings.isShown(offered: false))
        XCTAssertTrue(ProjectsSettings.rows(projects: projects, userId: "me", offered: false).isEmpty)
    }

    func testADEV357_projectsAreListedByName_withWhatThisPersonMayDo() {
        let rows = ProjectsSettings.rows(projects: projects, userId: "me", offered: true)
        XCTAssertEqual(rows.map(\.name), ["Apple", "Mango", "zebra"], "by name, whatever the case")
        XCTAssertEqual(rows.map(\.canEdit), [true, false, true], "the owner or a project admin edits")
        XCTAssertEqual(rows.map(\.canDelete), [false, false, true], "only the owner deletes")
        XCTAssertEqual(rows.first?.color, "#ff0000")
        XCTAssertEqual(rows.first?.project.id, "p1")
    }

    func testADEV357_aNewProjectNeedsAName() {
        XCTAssertEqual(ProjectsSettings.projectName(from: "  Launch  "), "Launch")
        XCTAssertNil(ProjectsSettings.projectName(from: "  \n"))
    }

    /// The door moved: New Project… is in Settings, not the Mac sidebar. Right-click editing stays.
    func testADEV357_theMacSidebarNoLongerMakesProjects_settingsDoes() throws {
        let sidebar = try RepositoryLocator.source(at: "Astrid Mac/Views/MacProjectSelection.swift")
        XCTAssertFalse(sidebar.contains("sidebar.newProject"))
        XCTAssertTrue(sidebar.contains("sidebar.project.edit"), "Edit Project… stays on the right-click")
        let macSettings = try RepositoryLocator.source(at: "Astrid Mac/App/MacSettingsView.swift")
        XCTAssertTrue(macSettings.contains("ProjectsSettingsView()"))
        let iosSettings = try RepositoryLocator.source(at: "Astrid App/Views/Settings/SettingsView.swift")
        XCTAssertTrue(iosSettings.contains("ProjectsSettingsView()"))
    }
}
