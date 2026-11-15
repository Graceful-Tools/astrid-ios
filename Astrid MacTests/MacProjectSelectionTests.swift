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

    func testAProjectExpandsToItsOwnRealLists_AITD674() {
        let lists = [
            TaskList(id: "a", name: "A", projectId: "p"),
            TaskList(id: "s", name: "Ready", projectId: "p", listType: "status"),
            TaskList(id: "v", name: "Smart", isVirtual: true, projectId: "p"),
            TaskList(id: "o", name: "Other", projectId: "q"),
        ]
        XCTAssertEqual(MacProjectSelection.lists(of: "p", in: lists).map(\.id), ["a"])
    }
}
