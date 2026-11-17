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
}
