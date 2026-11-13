//  TaskDetailHeaderIdentifierTests.swift
//  Regression guard for AITD-647 — "iOS task details".
//
//  1. On a board task the id sat in its own "Task ID" row. Jon: move it into the header, so it
//     reads "<id> Details" instead of "Task Details", and tapping the id copies it.
//  2. The iPad panel's arrow (AITD-607) aims at the selected LIST row; on a board there is no such
//     row, so the arrow pointed at nothing and the open-out-of-the-row motion read as broken.
//     Board → the old side panel, sliding in from the trailing edge, no arrow. List keeps both.

import XCTest
@testable import Astrid_App

final class TaskDetailHeaderIdentifierTests: XCTestCase {

    // MARK: - Header title

    func testNoIdentifierKeepsTaskDetails_AITD647() {
        let title = TaskDetailHeader.title(identifier: nil)
        XCTAssertNil(title.identifier)
        XCTAssertEqual(title.prefix, NSLocalizedString("tasks.task_details", comment: ""))
        XCTAssertEqual(title.suffix, "")
    }

    func testEmptyIdentifierKeepsTaskDetails_AITD647() {
        XCTAssertNil(TaskDetailHeader.title(identifier: "").identifier)
    }

    func testIdentifierReplacesTaskInTheTitle_AITD647() {
        let title = TaskDetailHeader.title(identifier: "AITD-647")
        XCTAssertEqual(title.identifier, "AITD-647")
        let format = NSLocalizedString("tasks.task_details_for_id", comment: "")
        XCTAssertEqual(title.prefix + "AITD-647" + title.suffix,
                       String(format: format, "AITD-647"),
                       "the three parts read back as the localized sentence, in its own word order")
    }

    func testEnglishReadsIdThenDetails_AITD647() {
        let title = TaskDetailHeader.splitTitle(format: "%@ Details", identifier: "AITD-647")
        XCTAssertEqual(title.prefix, "")
        XCTAssertEqual(title.identifier, "AITD-647")
        XCTAssertEqual(title.suffix, " Details")
    }

    func testOtherWordOrderIsKept_AITD647() {
        let title = TaskDetailHeader.splitTitle(format: "Détails de %@", identifier: "AITD-647")
        XCTAssertEqual(title.prefix, "Détails de ")
        XCTAssertEqual(title.suffix, "")
    }

    func testEveryLanguageHasThePlaceholder_AITD647() throws {
        let bundle = Bundle(for: TaskService.self)
        for lang in bundle.localizations where lang != "Base" {
            guard let path = bundle.path(forResource: lang, ofType: "lproj"),
                  let lproj = Bundle(path: path) else { continue }
            let value = lproj.localizedString(forKey: "tasks.task_details_for_id", value: nil, table: nil)
            XCTAssertTrue(value.contains("%@"), "\(lang): \(value)")
        }
    }

    // MARK: - Panel attachment

    func testListPanelPointsAtTheRow_AITD647() {
        XCTAssertTrue(DetailPanelChrome.pointsAtRow(viewMode: .list))
    }

    func testBoardPanelHasNoArrow_AITD647() {
        XCTAssertFalse(DetailPanelChrome.pointsAtRow(viewMode: .board),
                       "a board has no list row for the arrow to point at")
    }
}
