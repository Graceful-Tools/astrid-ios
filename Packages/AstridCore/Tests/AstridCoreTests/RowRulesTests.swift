import AstridCore
import XCTest

/// AITD-622: the detail layout, the leading picker, list chips and the day offset are the core's
/// (core 2b50348, AWTD2-216), so the Swift copies could go.
final class RowRulesTests: XCTestCase {

    func testAITD622_c8a1ff51_listModeOrderIsWhoDatePriorityLists() {
        let layout = CoreRules.detailLayout(displayMode: "list", isInProject: false, isReadOnly: false)
        XCTAssertEqual(layout?.fieldOrder, ["assignee", "when", "priority", "lists"])
    }

    func testAITD622_AITD332_boardStateRowOnlyOnABoardAndNeverReadOnly() {
        for mode in ["list", "project"] {
            XCTAssertEqual(CoreRules.detailLayout(displayMode: mode, isInProject: true,
                                                  isReadOnly: false)?.showsBoardState, true, mode)
            XCTAssertEqual(CoreRules.detailLayout(displayMode: mode, isInProject: false,
                                                  isReadOnly: false)?.showsBoardState, false, mode)
            XCTAssertEqual(CoreRules.detailLayout(displayMode: mode, isInProject: true,
                                                  isReadOnly: true)?.showsBoardState, false, mode)
        }
    }

    func testAITD622_AITD375_pickerAndOwnership() {
        let theirs = CoreRules.leadingPicker(displayMode: "list", surface: "listRow",
                                             assigneeId: "them", currentUserId: "me")
        XCTAssertEqual(theirs?.isSomeoneElsesTask, true)
        XCTAssertEqual(theirs?.pickerShowsProjectState, true)

        let mine = CoreRules.leadingPicker(displayMode: "list", surface: "listRow",
                                           assigneeId: "me", currentUserId: "me")
        XCTAssertEqual(mine?.isSomeoneElsesTask, false)
        XCTAssertEqual(mine?.pickerShowsProjectState, false)

        // Empty is nobody, not someone else.
        XCTAssertEqual(CoreRules.leadingPicker(displayMode: "list", surface: "listRow",
                                               assigneeId: "", currentUserId: "me")?.isSomeoneElsesTask,
                       false)
        XCTAssertEqual(CoreRules.leadingPicker(displayMode: "list", surface: "boardCard",
                                               assigneeId: "me", currentUserId: "me")?.pickerShowsProjectState,
                       true)
        XCTAssertEqual(CoreRules.leadingPicker(displayMode: "project", surface: "detail",
                                               assigneeId: "me", currentUserId: "me")?.pickerShowsProjectState,
                       true)
    }

    func testAITD622_chipsSkipColumnsAndHiddenListsInOrder() {
        let lists = [ChipListInput(id: "work", name: "Work", listType: nil),
                     ChipListInput(id: "doing", name: "Doing", listType: "status"),
                     ChipListInput(id: "viewed", name: "Viewed", listType: nil),
                     ChipListInput(id: "home", name: "Home", listType: "standard")]
        XCTAssertEqual(CoreRules.listChipIds(lists: lists, hiddenListIds: ["viewed"]), ["work", "home"])
        XCTAssertEqual(CoreRules.listChipIds(lists: [], hiddenListIds: []), [])
    }

    func testAITD622_dayOffsetReadsTimedInTheZoneAndAllDayAsItsDate() throws {
        let iso = ISO8601DateFormatter()
        let now = try XCTUnwrap(iso.date(from: "2026-10-17T03:00:00Z"))  // the 16th at UTC-8
        func days(_ date: String, allDay: Bool, offset: Int) -> Int? {
            CoreRules.dayOffset(to: iso.date(from: date)!, isAllDay: allDay, now: now, utcOffsetMinutes: offset)
        }
        XCTAssertEqual(days("2026-10-17T02:00:00Z", allDay: false, offset: -480), 0)
        XCTAssertEqual(days("2026-10-18T09:00:00Z", allDay: false, offset: -480), 2)
        XCTAssertEqual(days("2026-10-17T00:00:00Z", allDay: true, offset: -480), 1)
        XCTAssertEqual(days("2026-10-16T00:00:00Z", allDay: true, offset: 0), -1)
    }
}
