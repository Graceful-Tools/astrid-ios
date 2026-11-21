import XCTest

/// ADEV-173 — the completion filter and the completion sort say "To-do" / "Done", never
/// "Incomplete" / "Completed". The filter sheet, list Sort & Filters, the saved-filter summary
/// and the Mac list filter all read these keys, so the words are pinned here once.
final class ToDoDoneFilterWordingTests: XCTestCase {

    private func english() throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"),
            "the host app carries no English Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testADEV173_filterAndSortChoicesSayToDoAndDone() throws {
        let en = try english()
        XCTAssertEqual(en["tasks.incomplete"], "To-do")
        XCTAssertEqual(en["tasks.completed"], "Done")
        XCTAssertEqual(en["lists.incomplete_completed_recently"], "To-do + Done recently")
        XCTAssertEqual(en["filters.sort_incomplete_first"], "To-do First")
        XCTAssertEqual(en["filters.sort_completed_first"], "Done First")
    }

    func testADEV173_noFilterOrSortChoiceSaysComplete() throws {
        let en = try english()
        for key in ["tasks.incomplete", "tasks.completed", "lists.incomplete_completed_recently",
                    "filters.sort_incomplete_first", "filters.sort_completed_first"] {
            let value = try XCTUnwrap(en[key], key)
            XCTAssertFalse(value.lowercased().contains("complete"), "\(key) still says \(value)")
        }
    }
}
