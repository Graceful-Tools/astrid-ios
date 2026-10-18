//  ProjectFieldsTests.swift
//  AITD-491: a GitHub board's project fields in task details — the core's answer as the apps
//  read it, the words a value is drawn with, and the message a failed save shows.

import AstridCore
import XCTest
@testable import Astrid_App

final class ProjectFieldsTests: XCTestCase {

    /// The shape `taskProjectFields` answers with (astrid-core CONTRACTS D56).
    private let answer = """
    { "projectId": "p1", "rows": [
      { "id": "f-team", "remoteId": "R2", "name": "Team", "dataType": "single_select",
        "options": [{ "id": "o-ios", "name": "iOS", "color": "BLUE", "description": null }],
        "iterations": [], "mappedTo": null, "position": 1, "value": "o-ios" },
      { "id": "f-size", "remoteId": "R1", "name": "Size", "dataType": "number",
        "options": [], "iterations": [], "mappedTo": null, "position": 2, "value": 2.5 },
      { "id": "f-sprint", "remoteId": "R4", "name": "Sprint", "dataType": "iteration", "options": [],
        "iterations": [{ "id": "i1", "title": "Sprint 7", "startDate": "2026-10-13", "duration": 14, "completed": false }],
        "mappedTo": null, "position": 3, "value": "i1" },
      { "id": "f-ship", "remoteId": "R5", "name": "Ship", "dataType": "date", "options": [],
        "iterations": [], "mappedTo": null, "position": 4, "value": "2026-10-31" },
      { "id": "f-notes", "remoteId": "R6", "name": "Notes", "dataType": "text", "options": [],
        "iterations": [], "mappedTo": null, "position": 5, "value": null }
    ] }
    """

    private func decoded() throws -> TaskProjectFields {
        try JSONDecoder().decode(TaskProjectFields.self, from: Data(answer.utf8))
    }

    func testTheCoresAnswerDecodesWithEveryValueType_AITD491() throws {
        let fields = try decoded()
        XCTAssertEqual(fields.rows.map(\.id), ["f-team", "f-size", "f-sprint", "f-ship", "f-notes"])
        XCTAssertEqual(fields.rows[0].kind, .singleSelect)
        XCTAssertEqual(fields.rows[0].value, .text("o-ios"))
        XCTAssertEqual(fields.rows[1].value, .number(2.5))
        XCTAssertNil(fields.rows[4].value, "null is no value")
    }

    /// An option or iteration is drawn by its name, never its id; a day in the reader's format.
    func testAValueIsDrawnInWordsNotIds_AITD491() throws {
        let rows = try decoded().rows
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(rows[0].displayText(locale: english), "iOS")
        XCTAssertEqual(rows[1].displayText(locale: english), "2.5")
        XCTAssertEqual(rows[2].displayText(locale: english), "Sprint 7")
        XCTAssertEqual(rows[3].displayText(locale: english), "Oct 31, 2026")
        XCTAssertNil(rows[4].displayText(locale: english))
    }

    /// GitHub's day is midnight UTC. West of Greenwich that instant is the evening before, and a
    /// picker that drew it as-is would show the 30th for a task due the 31st.
    func testADayRoundTripsThroughTheDatePickerInAnyTimeZone_AITD491() throws {
        let day = try XCTUnwrap(ProjectFieldRow.day(from: "2026-10-31"))
        for zone in ["America/Los_Angeles", "Asia/Tokyo", "UTC"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let shown = ProjectFieldRow.localDay(day, in: calendar)
            XCTAssertEqual(ProjectFieldRow.dayText(from: shown, in: calendar), "2026-10-31", zone)
        }
    }

    func testAnEditorStartsFromTheValueAsTyped_AITD491() throws {
        let rows = try decoded().rows
        XCTAssertEqual(rows[1].editableText, "2.5")
        XCTAssertEqual(rows[4].editableText, "")
    }

    /// `sso_required` and `auth_required` are things a person can act on, so they get their own
    /// words, as on web; everything else is one message.
    func testAFailedSaveSaysWhatThePersonCanDo_AITD491() {
        let refused = { (code: String) in CoreFailure.testRefusal(status: 403, message: code) }
        XCTAssertEqual(ProjectFieldErrors.messageKey(for: refused("sso_required")),
                       "tasks.projectFields.errorSsoRequired")
        XCTAssertEqual(ProjectFieldErrors.messageKey(for: refused("auth_required")),
                       "tasks.projectFields.errorAuthRequired")
        XCTAssertEqual(ProjectFieldErrors.messageKey(for: refused("field_option_unknown")),
                       "tasks.projectFields.errorSaveFailed")
        XCTAssertEqual(ProjectFieldErrors.messageKey(for: URLError(.notConnectedToInternet)),
                       "tasks.projectFields.errorSaveFailed")
    }
}

private extension CoreFailure {
    static func testRefusal(status: Int, message: String) -> CoreFailure {
        let json = #"{"kind":"refused","message":"\#(message)","status":\#(status)}"#
        return try! JSONDecoder().decode(CoreFailure.self, from: Data(json.utf8))
    }
}
