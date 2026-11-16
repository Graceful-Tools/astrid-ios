//  MacProjectSelectionTests.swift
//  The Projects sidebar section (AITD-674, web AWTD-1660): its selection tag, its gate, and which
//  lists a project expands to.

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
