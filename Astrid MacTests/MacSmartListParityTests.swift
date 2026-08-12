//  MacSmartListParityTests.swift
//  Regression guard for Task 70d849f8 — "[mac] add save as favorites on mac app (currently works
//  on iOS). should have all the same capabilities".
//
//  The Mac filter sheet offers six controls — sort, completion, priority, due date, assigned-by
//  and repeating — but two of them fell out of the rules underneath it:
//
//  • `smartListUpdates` carried only sort + four filters, so saving a Smart List SILENTLY dropped
//    a repeating or assigned-by filter. The saved list then shows different tasks than the filter
//    that was saved, with nothing on screen to say so.
//  • `activeCount` counted the same four, so a repeating-only filter left the "Save as Smart
//    List" link disabled — which reads as "the feature is missing on Mac" — and also left the
//    toolbar badge unlit and Clear greyed out.
//
//  iOS enables its equivalent on any of the six (sort included) and saves repeating. These pin
//  the Mac to that.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSmartListParityTests: XCTestCase {

    // MARK: - The save must not drop filters

    /// The bug: a repeating filter set in the sheet has to survive into the saved list.
    func testSavingCarriesTheRepeatingFilter() {
        let u = MacListFilter.smartListUpdates(completion: "default", priority: "all",
                                               dueDate: "all", assignee: "all",
                                               sortBy: "auto", repeating: "repeating",
                                               assignedBy: "all")
        XCTAssertEqual(u["filterRepeating"] as? String, "repeating",
                       "A repeating filter must not vanish when saved as a Smart List")
    }

    func testSavingCarriesTheAssignedByFilter() {
        let u = MacListFilter.smartListUpdates(completion: "default", priority: "all",
                                               dueDate: "all", assignee: "all",
                                               sortBy: "auto", repeating: "all",
                                               assignedBy: "current_user")
        XCTAssertEqual(u["filterAssignedBy"] as? String, "current_user")
    }

    /// Everything the sheet can set is in the payload, and it is still a virtual list.
    func testSavingCarriesEveryFilterTheSheetOffers() {
        let u = MacListFilter.smartListUpdates(completion: "incomplete", priority: "3",
                                               dueDate: "today", assignee: "current_user",
                                               sortBy: "manual", repeating: "repeating",
                                               assignedBy: "not_current_user")
        XCTAssertEqual(u["isVirtual"] as? Bool, true)
        XCTAssertEqual(u["sortBy"] as? String, "manual")
        XCTAssertEqual(u["filterCompletion"] as? String, "incomplete")
        XCTAssertEqual(u["filterPriority"] as? String, "3")
        XCTAssertEqual(u["filterDueDate"] as? String, "today")
        XCTAssertEqual(u["filterAssignee"] as? String, "current_user")
        XCTAssertEqual(u["filterRepeating"] as? String, "repeating")
        XCTAssertEqual(u["filterAssignedBy"] as? String, "not_current_user")
    }

    // MARK: - The count that gates the link, the badge and Clear

    /// A repeating-only filter is an active filter. Counting it as zero is what makes the Mac
    /// look like it has no save-as feature at all.
    func testARepeatingOnlyFilterCounts() {
        XCTAssertEqual(MacListFilter.activeCount(completion: "default", priority: "all",
                                                 dueDate: "all", assignee: "all",
                                                 repeating: "repeating", assignedBy: "all"), 1)
    }

    func testAnAssignedByOnlyFilterCounts() {
        XCTAssertEqual(MacListFilter.activeCount(completion: "default", priority: "all",
                                                 dueDate: "all", assignee: "all",
                                                 repeating: "all", assignedBy: "current_user"), 1)
    }

    func testAllSixCount() {
        XCTAssertEqual(MacListFilter.activeCount(completion: "incomplete", priority: "3",
                                                 dueDate: "today", assignee: "current_user",
                                                 repeating: "repeating", assignedBy: "not_current_user"), 6)
    }

    /// Defaults still count as nothing, whichever way they are spelled.
    func testDefaultsStillCountAsInactive() {
        XCTAssertEqual(MacListFilter.activeCount(completion: "default", priority: "all",
                                                 dueDate: "all", assignee: "all",
                                                 repeating: "all", assignedBy: "all"), 0)
        XCTAssertEqual(MacListFilter.activeCount(completion: nil, priority: nil, dueDate: nil,
                                                 assignee: nil, repeating: nil, assignedBy: nil), 0)
    }

    /// Callers that predate the new dimensions must keep their old answer, not gain phantom
    /// filters — the badge on a list with no repeating filter must not light up.
    func testOmittingTheNewDimensionsIsUnchangedBehaviour() {
        XCTAssertEqual(MacListFilter.activeCount(completion: "incomplete", priority: "all",
                                                 dueDate: "all", assignee: "all"), 1)
    }
}
#endif
