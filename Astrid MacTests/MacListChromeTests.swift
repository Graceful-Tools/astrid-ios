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

    // MARK: one sort control, not two (AITD-305) — and it is in the header (AITD-522)

    /// AITD-522: "[mac] move list sort to the header and add gear for list settings."
    ///
    /// Sort used to hide in two places at once: inside the filter popover on a real list or My
    /// Tasks (AITD-305/467), and in the window toolbar everywhere else (AITD-509). It now sits in
    /// the strip above the rows on every list-mode selection, so the popovers no longer sort.
    ///
    /// AITD-552 then moved "the header" to the window toolbar's centre, beside the list/board
    /// picker — so this asks the title bar, and the strip carries no sort at all.
    func testSortSitsBesideTheModePickerForEveryListModeSelectionAITD552() {
        XCTAssertTrue(MacListChrome.titleBarCarriesListControls)
        for (isRealList, isMyTasks) in [(true, false), (false, true), (false, false)] {
            XCTAssertFalse(MacListChrome.headerShowsSort(hasSelection: true, isRealList: isRealList,
                                                         isMyTasks: isMyTasks, isListMode: true),
                           "the strip no longer sorts")
            XCTAssertTrue(MacListChrome.titleBarShowsSort(hasSelection: true, isRealList: isRealList,
                                                        isMyTasks: isMyTasks, isListMode: true),
                          "isRealList=\(isRealList) isMyTasks=\(isMyTasks): sort belongs in the header")
        }
        XCTAssertFalse(MacListChrome.titleBarShowsSort(hasSelection: true, isRealList: true,
                                                       isMyTasks: false, isListMode: false),
                       "a board is not a sorted row list")
        XCTAssertFalse(MacListChrome.titleBarShowsSort(hasSelection: false, isRealList: false,
                                                     isMyTasks: false, isListMode: true),
                       "nothing selected, nothing to sort")
    }

    /// Moving it to the header takes it OUT of the window toolbar (AITD-509 put it there).
    func testSortIsNoLongerAWindowToolbarItemAITD522() {
        XCTAssertFalse(MacListChrome.toolbarOffersSort)
        for (isRealList, isMyTasks) in [(true, false), (false, true), (false, false)] {
            XCTAssertFalse(MacListChrome.toolbarShowsSort(hasSelection: true, isRealList: isRealList,
                                                          isMyTasks: isMyTasks, isListMode: true))
        }
    }

    /// AITD-305's rule still holds: one sort control per selection. With sort in the header, the
    /// filter popovers drop their Sort section rather than offering it a second time.
    func testEverySelectionKeepsExactlyOneWayToSortAITD305() {
        XCTAssertFalse(MacListChrome.filterSheetOffersSort)
        XCTAssertFalse(MacListChrome.myTasksSheetOffersSort)
        for (isRealList, isMyTasks) in [(true, false), (false, true), (false, false)] {
            let sheetSorts = MacListChrome.sheetOffersSort(isRealList: isRealList, isMyTasks: isMyTasks,
                                                           isListMode: true)
            let headerSorts = [
                MacListChrome.headerShowsSort(hasSelection: true, isRealList: isRealList,
                                              isMyTasks: isMyTasks, isListMode: true),
                MacListChrome.titleBarShowsSort(hasSelection: true, isRealList: isRealList,
                                                isMyTasks: isMyTasks, isListMode: true),
                MacListChrome.toolbarShowsSort(hasSelection: true, isRealList: isRealList,
                                               isMyTasks: isMyTasks, isListMode: true),
            ].filter { $0 }.count == 1
            XCTAssertNotEqual(sheetSorts, headerSorts,
                              "isRealList=\(isRealList) isMyTasks=\(isMyTasks) offers sort \(sheetSorts && headerSorts ? "twice" : "not at all")")
        }
    }

    /// The filter editor writes to a real list's saved filters; My Tasks keeps its own prefs and a
    /// saved-filter list owns no filters of its own.
    func testFilterShowsOnlyForARealListInListMode() {
        XCTAssertTrue(MacListChrome.showsFilter(isRealList: true, isListMode: true))
        XCTAssertFalse(MacListChrome.showsFilter(isRealList: false, isListMode: true))
        XCTAssertFalse(MacListChrome.showsFilter(isRealList: true, isListMode: false))
    }

    /// Filter stays out of the window toolbar: it opens the list's sheet, which belongs to the rows.
    func testFilterIsNotAWindowToolbarItem() {
        XCTAssertFalse(MacListChrome.toolbarOffersFilter)
    }

    // MARK: the strip (AITD-509, AITD-522)

    /// With nothing to show there is still no strip — AITD-509's complaint was an empty-ish row.
    func testNoControlsMeansNoStrip() {
        XCTAssertFalse(MacListChrome.showsStrip(showsSort: false, showsFilter: false,
                                                showsMyTasksFilter: false, showsListMenu: false))
    }

    /// Each control in the header is enough to draw it — sort included, now that it lives there.
    func testTheStripDrawsForEachHeaderControlAITD522() {
        XCTAssertTrue(MacListChrome.showsStrip(showsSort: true, showsFilter: false, showsMyTasksFilter: false, showsListMenu: false))
        XCTAssertTrue(MacListChrome.showsStrip(showsSort: false, showsFilter: true, showsMyTasksFilter: false, showsListMenu: false))
        XCTAssertTrue(MacListChrome.showsStrip(showsSort: false, showsFilter: false, showsMyTasksFilter: true, showsListMenu: false))
        XCTAssertTrue(MacListChrome.showsStrip(showsSort: false, showsFilter: false, showsMyTasksFilter: false, showsListMenu: true))
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
