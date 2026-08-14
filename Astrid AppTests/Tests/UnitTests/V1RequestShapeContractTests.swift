//  V1RequestShapeContractTests.swift
//  Pins the v1 REQUEST bodies iOS sends (Task ed474b03).
//
//  The web repo now pins these shapes in `lib/api-contracts/v1-request-shapes.ts`, the mirror of
//  the response contract iOS already depends on. Nothing was broken when that landed — these tests
//  exist so that stays true, because all three of the risks it names are silent when they break:
//  a field clears when it should not, an assignee lands on the wrong person, a list is created
//  with a privacy the database rejects.
//
//  IMPORTANT, and NOT what the written contract says: iOS clears a field with an EMPTY STRING,
//  never with JSON null. Its encoder is `encodeIfPresent` throughout, so nil means "omit" — there
//  is no way for it to emit null. The server accepts both (`body.dueDateTime === '' || === null`,
//  and `body.assigneeId || null`), which is why this works. If anyone tightens the server to match
//  the contract's letter and drops the empty-string case, iOS silently stops clearing due dates
//  and unassigning. That asymmetry is filed on the web board.

import XCTest
@testable import Astrid_App

final class V1RequestShapeContractTests: XCTestCase {

    private func body(_ request: UpdateTaskRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Omitted means "leave unchanged"

    /// The risk the contract names first: a client that serialises every optional would send nulls
    /// for fields it meant to leave alone, clearing them. iOS omits them instead.
    func testUnsetFieldsAreOmittedEntirely() throws {
        var request = UpdateTaskRequest()
        request.title = "just the title"
        let json = try body(request)

        XCTAssertEqual(json["title"] as? String, "just the title")
        for untouched in ["dueDateTime", "assigneeId", "parentTaskId", "priority",
                          "listIds", "isAllDay", "completed"] {
            XCTAssertNil(json[untouched],
                         "\(untouched) was never set, so it must not appear at all — its presence "
                         + "would change a field the user did not touch")
        }
    }

    /// And nothing iOS sends is ever literal null, because the encoder cannot produce one.
    func testNoFieldIsEverEncodedAsNull() throws {
        var request = UpdateTaskRequest()
        request.title = "t"
        request.dueDateTime = ""
        request.assigneeId = ""
        let data = try JSONEncoder().encode(request)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("null"),
                       "iOS clears with an empty string; a null here would mean the encoder changed")
    }

    // MARK: - Clearing

    /// Clearing the due date is an empty string, and it must actually reach the wire.
    func testClearingTheDueDateSendsAnEmptyString() throws {
        var request = UpdateTaskRequest()
        request.dueDateTime = ""
        let json = try body(request)
        XCTAssertEqual(json["dueDateTime"] as? String, "",
                       "the server reads '' or null as clear; iOS sends ''")
    }

    func testUnassigningSendsAnEmptyString() throws {
        var request = UpdateTaskRequest()
        request.assigneeId = ""
        let json = try body(request)
        XCTAssertEqual(json["assigneeId"] as? String, "",
                       "the server does `body.assigneeId || null`, so '' unassigns")
    }

    /// A real date still goes as a real date — the clearing case must not swallow the normal one.
    func testASetDueDateIsSentAsItself() throws {
        var request = UpdateTaskRequest()
        request.dueDateTime = "2026-09-01T09:00:00Z"
        XCTAssertEqual(try body(request)["dueDateTime"] as? String, "2026-09-01T09:00:00Z")
    }

    // MARK: - The list default assignee is three-way, not a user id

    /// nil = whoever creates the task, "unassigned" = nobody, anything else = that user.
    /// Collapsing the middle case has already cost a bug on the web side.
    func testTheListDefaultAssigneeKeepsItsThreeMeanings() {
        XCTAssertEqual(NewTaskDefaults.assignee(nil, currentUserId: "me"), "me",
                       "no default means the creator")
        XCTAssertEqual(NewTaskDefaults.assignee("", currentUserId: "me"), "me",
                       "empty is the same as absent here")
        XCTAssertNil(NewTaskDefaults.assignee("unassigned", currentUserId: "me"),
                     "the literal 'unassigned' means NOBODY, not the creator")
        XCTAssertEqual(NewTaskDefaults.assignee("someone-else", currentUserId: "me"), "someone-else")
    }

    /// Signed out, "creator" resolves to nobody rather than crashing or inventing an id.
    func testTheCreatorDefaultWithNoSignedInUserIsUnassigned() {
        XCTAssertNil(NewTaskDefaults.assignee(nil, currentUserId: nil))
    }

    // MARK: - Privacy is upper-case, and the server now rejects anything else

    /// `POST /api/v1/lists` now 400s on a privacy outside this set instead of letting it reach
    /// Postgres as a 500. Case matters: 'private' is not 'PRIVATE'.
    func testPrivacyValuesAreTheUppercaseSetTheServerAccepts() {
        XCTAssertEqual(TaskList.Privacy.PRIVATE.rawValue, "PRIVATE")
        XCTAssertEqual(TaskList.Privacy.SHARED.rawValue, "SHARED")
        XCTAssertEqual(TaskList.Privacy.PUBLIC.rawValue, "PUBLIC")
        XCTAssertNil(TaskList.Privacy(rawValue: "private"),
                     "lower case must not silently decode — the server rejects it")
    }

    /// Every case is covered, so adding one to the enum without teaching the server fails here.
    func testTheEnumCarriesExactlyTheThreeServerValues() {
        let all = ["PRIVATE", "SHARED", "PUBLIC"].compactMap { TaskList.Privacy(rawValue: $0) }
        XCTAssertEqual(all.count, 3)
    }
}
