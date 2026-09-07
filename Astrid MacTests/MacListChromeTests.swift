//  MacListChromeTests.swift
//  Regression tests for Tasks 9998d83a ("sort / filter button should be above task list, not the
//  message list") and 10d2cd34 ("there is an extra + button above the message list. remove it").
//
//  One cause: in 3-column mode the detail area is [task list | chat], but the window toolbar spans
//  BOTH. Anything at .primaryAction right-aligns at the window's trailing edge — over the chat
//  column — so controls that act on the task list appeared to belong to the message list.

import XCTest
@testable import Astrid_Mac

final class MacListChromeTests: XCTestCase {

    // MARK: sort / filter belong to the list (9998d83a)

    /// Sort acts on the rows, so it rides with the rows — in every layout, not only the wide one.
    func testSortSitsWithTheListWheneverThereAreRowsToSort() {
        XCTAssertTrue(MacListChrome.showsSort(hasSelection: true, isListMode: true,
                                              filterSheetOffersSort: false))
        XCTAssertFalse(MacListChrome.showsSort(hasSelection: false, isListMode: true,
                                               filterSheetOffersSort: false),
                       "nothing selected, nothing to sort")
        XCTAssertFalse(MacListChrome.showsSort(hasSelection: true, isListMode: false,
                                               filterSheetOffersSort: false),
                       "board and chat are not a sorted row list")
    }

    // MARK: one sort control, not two (AITD-305)

    /// AITD-305: "remove the duplicative sort / menu icon above the list. keep the one that has
    /// all the things."
    ///
    /// On a real list the strip drew BOTH the sort menu and the filter button, and
    /// `MacFilterSheet` opens with a Sort section of its own — so sort was offered twice, three
    /// pixels apart. The filter sheet is the one that has all the things (sort + six filters +
    /// saved filter + subtasks), so the standalone menu is the one that goes.
    func testRealListDropsTheStandaloneSortMenuBecauseTheFilterSheetAlreadySortsAITD305() {
        XCTAssertTrue(MacListChrome.filterSheetOffersSort,
                      "MacFilterSheet's Sort section is what makes the separate menu redundant")
        XCTAssertFalse(MacListChrome.showsSort(hasSelection: true, isListMode: true,
                                               filterSheetOffersSort: true),
                       "the filter sheet already sorts — a second sort icon is the duplicate")
    }

    /// Removing it must not strip the capability. Every selection that shows rows still reaches
    /// sort through exactly ONE control — the sheet where a list filter exists, the standalone
    /// menu where it does not (a saved-filter list, and My Tasks, whose sheet has no sort).
    func testEverySelectionKeepsExactlyOneWayToSortAITD305() {
        for isRealList in [true, false] {
            let sheetSorts = MacListChrome.showsFilter(isRealList: isRealList, isListMode: true)
                && MacListChrome.filterSheetOffersSort
            let menuShows = MacListChrome.showsSort(hasSelection: true, isListMode: true,
                                                    filterSheetOffersSort: sheetSorts)
            XCTAssertNotEqual(sheetSorts, menuShows,
                              "isRealList=\(isRealList) offers sort \(sheetSorts && menuShows ? "twice" : "not at all")")
        }
    }

    /// My Tasks is virtual, so no list filter sheet stands behind it, and its own sheet offers the
    /// three iOS filters and no sort — it keeps the standalone menu.
    func testMyTasksKeepsTheSortMenuAITD305() {
        let sheetSorts = MacListChrome.showsFilter(isRealList: false, isListMode: true)
            && MacListChrome.filterSheetOffersSort
        XCTAssertTrue(MacListChrome.showsSort(hasSelection: true, isListMode: true,
                                              filterSheetOffersSort: sheetSorts),
                      "My Tasks would lose sort entirely")
    }

    /// The filter editor writes to a real list's saved filters; My Tasks keeps its own prefs and a
    /// saved-filter list owns no filters of its own.
    func testFilterShowsOnlyForARealListInListMode() {
        XCTAssertTrue(MacListChrome.showsFilter(isRealList: true, isListMode: true))
        XCTAssertFalse(MacListChrome.showsFilter(isRealList: false, isListMode: true))
        XCTAssertFalse(MacListChrome.showsFilter(isRealList: true, isListMode: false))
    }

    /// The point of the task: these controls must NOT be window-toolbar items, because the window
    /// toolbar's trailing edge is the chat column.
    func testTheseControlsAreNotWindowToolbarItems() {
        XCTAssertFalse(MacListChrome.toolbarOffersSortOrFilter)
    }

    // MARK: the extra + (10d2cd34)

    /// The toolbar "+" is gone.
    func testTheToolbarNoLongerOffersANewTaskButton() {
        XCTAssertFalse(MacListChrome.toolbarOffersNewTask)
    }

    /// …and removing it strips no capability: everywhere the old toolbar "+" was ENABLED
    /// (a list selected, not a virtual selection) the quick-add bar is showing, which adds a task
    /// and opens its details. This is the assertion that makes the removal safe rather than lossy.
    func testEveryStateThatCouldAddViaTheToolbarCanStillAdd() {
        for isMyTasks in [true, false] {
            for isVirtual in [true, false] {
                let oldToolbarPlusWasEnabled = !isVirtual        // and a list was selected
                guard oldToolbarPlusWasEnabled else { continue }
                XCTAssertTrue(MacAddTaskBar.isVisible(isVirtualSelection: isVirtual,
                                                      hasSelection: true, isMyTasks: isMyTasks),
                              "no way left to add (virtual=\(isVirtual), myTasks=\(isMyTasks))")
            }
        }
    }

    /// The quick-add is strictly MORE available than the button that was removed: My Tasks can add
    /// from the bar, where the toolbar "+" was disabled.
    func testQuickAddCoversMyTasksWhereTheToolbarPlusWasDisabled() {
        XCTAssertTrue(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: true,
                                              isMyTasks: true))
    }

    /// With nothing selected there is nothing to add into — and nothing offering to.
    func testNoSelectionOffersNoAdd() {
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: false, hasSelection: false))
    }
}
