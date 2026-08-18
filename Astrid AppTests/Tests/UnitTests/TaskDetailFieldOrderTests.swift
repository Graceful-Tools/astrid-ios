//  TaskDetailFieldOrderTests.swift
//  Regression guard for Task c8a1ff51 — "Update order of fields in list style task details view
//  to have continuity".
//
//  Jon: "Order (under task title): Who, Date, Priority, Lists. For Priority use '!!!' as icon
//  not a flag. Implement same order on all interfaces for list mode (iOS, Mac, web)."
//
//  Both platforms had Priority first and Who second — the same wrong order twice, which is what
//  two views deciding for themselves produces. The ask is continuity, so the order is stated
//  once and each platform is pinned to it.

import XCTest
@testable import Astrid_App

final class TaskDetailFieldOrderTests: XCTestCase {

    // MARK: - The order itself

    func testListModeOrderIsWhoDatePriorityLists() {
        XCTAssertEqual(TaskDetailFieldOrder.listMode, [.assignee, .when, .priority, .lists])
    }

    // MARK: - The priority row's mark

    /// THE ASK: "!!!" as the icon, not a flag.
    func testThePriorityRowIsMarkedWithThreeBangs() {
        XCTAssertEqual(PriorityGlyph.rowIcon, "!!!")
    }

    /// And the row icon is the same vocabulary the marks themselves use — it is the HIGH mark,
    /// not an unrelated string that happens to look similar.
    func testTheRowIconIsTheHighPriorityMark() {
        XCTAssertEqual(PriorityGlyph.rowIcon, PriorityGlyph.symbol(.high))
    }

    func testEachPriorityHasItsMark() {
        XCTAssertEqual(PriorityGlyph.symbol(.none), "○")
        XCTAssertEqual(PriorityGlyph.symbol(.low), "!")
        XCTAssertEqual(PriorityGlyph.symbol(.medium), "!!")
        XCTAssertEqual(PriorityGlyph.symbol(.high), "!!!")
    }

    // MARK: - iOS follows it

    /// The iOS detail builds its rows inline in SwiftUI, so it cannot consume the list directly.
    /// Pin the order it actually emits: the four rows must appear in the file in this sequence.
    ///
    /// A flag icon on the priority row is the other half, and would silently come back with any
    /// copy-paste of a neighbouring row.
    func testTheIOSDetailEmitsTheRowsInOrder() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Views/Tasks/TaskDetailViewNew.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        let markers = [
            ("Who", "tasks.assignee"),
            ("Date", "tasks.when"),
            ("Priority", "tasks.priority"),
            ("Lists", "navigation.lists"),
        ]
        var previous = source.startIndex
        var previousName = "the title"
        for (name, key) in markers {
            guard let range = source.range(of: "TwoColumnRow(label: NSLocalizedString(\"\(key)\"",
                                           range: previous..<source.endIndex) else {
                return XCTFail("No \(name) row found after \(previousName)")
            }
            previous = range.upperBound
            previousName = name
        }

        XCTAssertFalse(source.contains("icon: \"flag\""),
                       "The priority row is marked with \(PriorityGlyph.rowIcon), not a flag")
    }
}
