import XCTest
@testable import Astrid_App

/// What an empty board column says (ADEV-81). Every column used to say the list's
/// "Ready to capture your thoughts?" line, which means nothing in Waiting or Doing; each column
/// now speaks to its own state, and the Mac board reads the same decision.
final class BoardColumnEmptyMessageTests: XCTestCase {
    private func column(_ id: String, _ kind: ProjectBoardColumnKind = .status) -> ProjectBoardColumn {
        ProjectBoardColumn(id: id, name: id, description: "", kind: kind)
    }

    func testEachStandardColumnHasItsOwnMessage_ADEV81() {
        XCTAssertEqual(BoardColumnEmptyMessage.decide(column(VIRTUAL_INBOX_COLUMN_ID, .inbox)), .inbox)
        XCTAssertEqual(BoardColumnEmptyMessage.decide(column("ready")), .ready)
        XCTAssertEqual(BoardColumnEmptyMessage.decide(column("doing")), .doing)
        XCTAssertEqual(BoardColumnEmptyMessage.decide(column("waiting")), .waiting)
        XCTAssertEqual(BoardColumnEmptyMessage.decide(column(VIRTUAL_DONE_COLUMN_ID, .done)), .done)
    }

    func testACustomColumnGetsTheGeneralBoardMessage_ADEV81() {
        XCTAssertEqual(BoardColumnEmptyMessage.decide(column("custom-review")), .custom)
    }

    func testNoColumnSaysTheListsCaptureYourThoughtsLine_ADEV81() {
        let all: [BoardColumnEmptyMessage] = [.inbox, .ready, .doing, .waiting, .done, .custom]
        let listDefault = NSLocalizedString("empty_state.default", comment: "")
        var seen = Set<String>()
        for message in all {
            XCTAssertNotEqual(message.text, message.key, "\(message.key) needs a string in Localizable.strings")
            XCTAssertNotEqual(message.text, listDefault, "\(message.key) must not reuse the list's message")
            XCTAssertTrue(seen.insert(message.text).inserted, "\(message.key) repeats another column's message")
        }
    }

    // MARK: ADEV-320 — the core names the message (core ADEV-221)

    /// The board answer carries each column's `emptyMessageKey`; the core's choice is the one shown,
    /// not a Swift copy of the rule.
    func testTheCoresEmptyMessageKeyDecides_ADEV320() throws {
        let json = #"{"id":"custom-qa","name":"QA","description":"","kind":"status","ids":[],"emptyMessageKey":"board.empty.waiting"}"#
        let col = try JSONDecoder().decode(BoardModel.Column.self, from: Data(json.utf8))
        XCTAssertEqual(col.column.emptyMessageKey, "board.empty.waiting")
        XCTAssertEqual(BoardColumnEmptyMessage.decide(col.column), .waiting)
    }

    /// Every key core catalogues maps to a message; an unknown key or none falls back to the column.
    func testEveryCoreKeyMapsAndUnknownFallsBack_ADEV320() {
        let pairs: [(String, BoardColumnEmptyMessage)] = [
            ("board.empty.inbox", .inbox), ("board.empty.ready", .ready), ("board.empty.doing", .doing),
            ("board.empty.waiting", .waiting), ("board.empty.done", .done), ("board.empty.custom", .custom),
        ]
        for (key, message) in pairs {
            let col = ProjectBoardColumn(id: "custom-x", name: "X", description: "", kind: .status, emptyMessageKey: key)
            XCTAssertEqual(BoardColumnEmptyMessage.decide(col), message, key)
        }
        let unknown = ProjectBoardColumn(id: "doing", name: "Doing", description: "", kind: .status, emptyMessageKey: "board.empty.someday")
        XCTAssertEqual(BoardColumnEmptyMessage.decide(unknown), .doing)
    }
}
