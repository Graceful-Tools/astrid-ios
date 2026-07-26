//  MacQuickAddDefaultsTests.swift
//  RED-first (as requested): a Mac quick-add must apply the LIST'S DEFAULTS the way iOS does —
//  default priority, due date/time, repeat, assignee and privacy — and anything the user typed or
//  chose must OVERRIDE those defaults, never the other way round.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacQuickAddDefaultsTests: XCTestCase {

    private func list(defaultPriority: Int? = nil, defaultDueDate: String? = nil,
                      defaultDueTime: String? = nil, defaultRepeating: String? = nil,
                      defaultAssigneeId: String? = nil, defaultIsPrivate: Bool? = nil) -> TaskList {
        var l = TaskList(id: "list-1", name: "Work")
        l.defaultPriority = defaultPriority
        l.defaultDueDate = defaultDueDate
        l.defaultDueTime = defaultDueTime
        l.defaultRepeating = defaultRepeating
        l.defaultAssigneeId = defaultAssigneeId
        l.defaultIsPrivate = defaultIsPrivate
        return l
    }

    // MARK: - Defaults are applied

    func testListDefaultPriorityIsApplied() {
        let args = MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: "list-1",
                                        lists: [list(defaultPriority: 2)])
        XCTAssertEqual(args?.priority, 2, "The list's default priority must be applied")
    }

    func testListDefaultDueDateIsApplied() {
        let args = MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: "list-1",
                                        lists: [list(defaultDueDate: "tomorrow")])
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let due = try? XCTUnwrap(args?.whenDate)
        XCTAssertNotNil(due)
        XCTAssertTrue(Calendar.current.isDate(due!, inSameDayAs: expected),
                      "Default due date 'tomorrow' must land on tomorrow")
    }

    func testListDefaultRepeatIsApplied() {
        let args = MacQuickAdd.makeArgs(rawText: "Water plants", selectedListId: "list-1",
                                        lists: [list(defaultRepeating: "weekly")])
        XCTAssertEqual(args?.repeating, "weekly")
    }

    func testListDefaultAssigneeAndPrivacyAreApplied() {
        let args = MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: "list-1",
                                        lists: [list(defaultAssigneeId: "user-9", defaultIsPrivate: true)])
        XCTAssertEqual(args?.assigneeId, "user-9")
        XCTAssertEqual(args?.isPrivate, true)
    }

    /// A default of 0/"none" means "no default" — it must not stamp priority 0 over nothing.
    func testZeroAndNoneDefaultsAreTreatedAsUnset() {
        let args = MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: "list-1",
                                        lists: [list(defaultPriority: 0, defaultDueDate: "none")])
        XCTAssertNil(args?.priority)
        XCTAssertNil(args?.whenDate)
    }

    // MARK: - What the user says wins

    func testTypedPriorityOverridesTheListDefault() {
        let args = MacQuickAdd.makeArgs(rawText: "Ship release urgent", selectedListId: "list-1",
                                        lists: [list(defaultPriority: 1)])
        XCTAssertEqual(args?.priority, 3, "'urgent' must beat the list's default priority")
    }

    func testTypedDateOverridesTheListDefault() {
        let args = MacQuickAdd.makeArgs(rawText: "Pay rent tomorrow", selectedListId: "list-1",
                                        lists: [list(defaultDueDate: "next_week")])
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(Calendar.current.isDate(try! XCTUnwrap(args?.whenDate), inSameDayAs: tomorrow),
                      "A typed date must beat the list default")
    }

    /// The quick-add checkbox lets the user pick a priority for the next task; that choice must
    /// beat the list default (this is the override iOS offers).
    func testCheckboxOverrideBeatsTheListDefault() {
        let args = MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: "list-1",
                                        lists: [list(defaultPriority: 1)], priorityOverride: 3)
        XCTAssertEqual(args?.priority, 3)
    }

    /// …but typed text still beats an override, so the last thing the user expressed wins.
    func testTypedPriorityBeatsTheCheckboxOverride() {
        let args = MacQuickAdd.makeArgs(rawText: "Ship it urgent", selectedListId: "list-1",
                                        lists: [list(defaultPriority: 1)], priorityOverride: 1)
        XCTAssertEqual(args?.priority, 3)
    }

    /// My Tasks has no list, so there are no list defaults to apply.
    func testVirtualSelectionAppliesNoListDefaults() {
        let args = MacQuickAdd.makeArgs(rawText: "Buy milk", selectedListId: "__my_tasks__",
                                        lists: [list(defaultPriority: 2)], selectionIsVirtual: true)
        XCTAssertNil(args?.priority)
        XCTAssertTrue(args?.listIds.isEmpty ?? false)
    }
}
#endif
