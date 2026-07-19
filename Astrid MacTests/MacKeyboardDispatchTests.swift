//  MacKeyboardDispatchTests.swift
//  Astrid for Mac — regression for Task 9a60b697: every bare-key shortcut must be dispatched.
//
//  RED before the fix: MacAppModel.handledActions held only 4 of the 22 shared actions
//  (newTask / completeTask / deleteTask / showShortcuts) — the ⌘/ help sheet advertised 18
//  keys that did nothing. These lock the full dispatch table + the pure effect mapping/date math.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacKeyboardDispatchTests: XCTestCase {

    /// The core regression: NO dead keys — every action in the shared table is handled.
    func testEveryShortcutActionIsHandled() {
        for action in ShortcutAction.allCases {
            XCTAssertTrue(MacAppModel.handledActions.contains(action),
                          "Shortcut \(action) is advertised but not dispatched")
        }
        XCTAssertEqual(MacAppModel.handledActions.count, ShortcutAction.allCases.count)
    }

    /// Data-mutation actions map to the right pure effect.
    func testDataEffectMapping() {
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .priorityNone), .priority(0))
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .priorityLow), .priority(1))
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .priorityMedium), .priority(2))
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .priorityHigh), .priority(3))
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .dueDateEarlier), .shiftDueDays(-1))
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .dueDateLater), .shiftDueDays(1))
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .postpone), .shiftDueDays(7))
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .removeDueDate), .clearDueDate)
        XCTAssertEqual(MacShortcutEffect.dataEffect(for: .assignNoOne), .assignNoOne)
        // Non-data actions have no data effect.
        XCTAssertNil(MacShortcutEffect.dataEffect(for: .newTask))
        XCTAssertNil(MacShortcutEffect.dataEffect(for: .editTitle))
    }

    /// Field-focus actions map to the right detail field.
    func testFocusFieldMapping() {
        XCTAssertEqual(MacShortcutEffect.focusField(for: .jumpToDate), .date)
        XCTAssertEqual(MacShortcutEffect.focusField(for: .editLists), .lists)
        XCTAssertEqual(MacShortcutEffect.focusField(for: .editDescription), .description)
        XCTAssertEqual(MacShortcutEffect.focusField(for: .addComment), .comment)
        XCTAssertNil(MacShortcutEffect.focusField(for: .priorityHigh))
    }

    /// Every action is EITHER a data effect, a focus field, or one of the view/service actions —
    /// no action falls through unhandled (guards the `perform` switch exhaustiveness).
    func testNoActionFallsThrough() {
        let viewOrService: Set<ShortcutAction> = [
            .newTask, .completeTask, .deleteTask, .showShortcuts,
            .editTitle, .togglePanel, .cycleFilters, .selectPrevious, .selectNext,
        ]
        for action in ShortcutAction.allCases {
            let handled = MacShortcutEffect.dataEffect(for: action) != nil
                || MacShortcutEffect.focusField(for: action) != nil
                || viewOrService.contains(action)
            XCTAssertTrue(handled, "\(action) is not routed anywhere")
        }
    }

    /// Due-date shift math: relative to the existing due date, or to today when undated.
    func testShiftedDueDateMath() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        let due = cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        // With an existing due date, shift from it.
        XCTAssertEqual(MacShortcutEffect.shiftedDueDate(current: due, days: 1, calendar: cal, today: today),
                       cal.date(from: DateComponents(year: 2026, month: 1, day: 11)))
        XCTAssertEqual(MacShortcutEffect.shiftedDueDate(current: due, days: -1, calendar: cal, today: today),
                       cal.date(from: DateComponents(year: 2026, month: 1, day: 9)))
        XCTAssertEqual(MacShortcutEffect.shiftedDueDate(current: due, days: 7, calendar: cal, today: today),
                       cal.date(from: DateComponents(year: 2026, month: 1, day: 17)))

        // Undated task: shift is relative to today.
        XCTAssertEqual(MacShortcutEffect.shiftedDueDate(current: nil, days: 1, calendar: cal, today: today),
                       cal.date(from: DateComponents(year: 2026, month: 7, day: 19)))
        XCTAssertEqual(MacShortcutEffect.shiftedDueDate(current: nil, days: 7, calendar: cal, today: today),
                       cal.date(from: DateComponents(year: 2026, month: 7, day: 25)))
    }
}
#endif
