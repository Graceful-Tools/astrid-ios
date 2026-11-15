//  ProjectBoardListTests.swift
//  ADEV-3: "The Astrid-dev project has all the tasks in each list in iOS. It should not."
//  The iOS board asked the core about the project's FIRST domain list rather than the list it was
//  opened from, so once a project held several lists the order, the Done window and every
//  "+ Add task" went to whichever list came first. (The core drew the whole project; D69 fixes it.)

import XCTest
@testable import Astrid_App

final class ProjectBoardListTests: XCTestCase {

    private func list(_ id: String, project: String?, type: String? = "regular") -> TaskList {
        var list = TestHelpers.createTestList(id: id, name: id)
        list.projectId = project
        list.listType = type
        return list
    }

    private lazy var lists = [
        list("web", project: "dev"),
        list("ios", project: "dev"),
        list("status", project: "dev", type: "status"),
        list("other", project: "elsewhere"),
    ]

    func testTheBoardIsTheListItWasOpenedFrom_ADEV3() {
        XCTAssertEqual(ProjectStatusBoardView.boardList(openedListId: "ios", projectId: "dev", lists: lists)?.id,
                       "ios", "not the project's first list")
        XCTAssertEqual(ProjectStatusBoardView.boardList(openedListId: "web", projectId: "dev", lists: lists)?.id,
                       "web")
    }

    func testWithoutAnOpenedListItFallsBackToTheFirstDomainList_ADEV3() {
        XCTAssertEqual(ProjectStatusBoardView.boardList(openedListId: nil, projectId: "dev", lists: lists)?.id,
                       "web")
    }

    func testAListOfAnotherProjectOrAStatusListIsNotTheBoardsList_ADEV3() {
        XCTAssertEqual(ProjectStatusBoardView.boardList(openedListId: "other", projectId: "dev", lists: lists)?.id,
                       "web")
        XCTAssertEqual(ProjectStatusBoardView.boardList(openedListId: "status", projectId: "dev", lists: lists)?.id,
                       "web")
    }
}
