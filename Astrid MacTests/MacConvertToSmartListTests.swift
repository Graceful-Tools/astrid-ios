//  MacConvertToSmartListTests.swift
//  Regression guard for Task 0e09b224 — "[mac] When saving a list as 'smart list' it should turn
//  into a smart list, not create another list with the same name as a smart list. See web."
//
//  Web has no "save as" action: components/list-sort-and-filters.tsx renders a Saved Filter
//  checkbox that flips `isVirtual` on the list you are already looking at. iOS has the same
//  toggle. The Mac alone created a NEW list and copied the filters onto it — and pre-filled the
//  name with the current list's name, so you reliably ended up with two lists called the same
//  thing, one real and one virtual.
//
//  Converting is reversible: toggling back off makes it a normal list again, and no task ever
//  moves, because `isVirtual` changes how membership is DECIDED rather than what belongs.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacConvertToSmartListTests: XCTestCase {

    private func macSource(_ relative: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root
            .appendingPathComponent("Astrid Mac")
            .appendingPathComponent(relative), encoding: .utf8)
    }

    /// Converting turns the CURRENT list virtual, carrying the filters it already has.
    func testConversionMarksTheListVirtual() {
        let u = MacListFilter.smartListUpdates(completion: "incomplete", priority: "all",
                                               dueDate: "all", assignee: "all",
                                               sortBy: "auto", repeating: "all",
                                               assignedBy: "all")
        XCTAssertEqual(u["isVirtual"] as? Bool, true)
    }

    /// Reversible: turning it back off is a plain flag flip, not a second concept.
    func testTurningItBackOffIsJustTheFlag() {
        XCTAssertEqual(MacListFilter.revertToNormalListUpdates()["isVirtual"] as? Bool, false)
    }

    /// Reverting must not disturb the filters — they stay on the list, simply no longer deciding
    /// membership. Clearing them here would silently destroy the user's filter setup.
    func testRevertingLeavesTheFiltersAlone() {
        let u = MacListFilter.revertToNormalListUpdates()
        XCTAssertEqual(u.count, 1, "Reverting touches isVirtual and nothing else: \(u)")
    }
}
#endif
