//  MacAddTaskBarTests.swift
//  Astrid for Mac — Task bf998f4e: the bottom Add-task bar shows only for a real list.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAddTaskBarTests: XCTestCase {

    func testVisibleForRealList() {
        XCTAssertTrue(MacAddTaskBar.isVisible(isVirtualSelection: false, hasSelection: true))
    }

    /// My Tasks now has a quick-add too (iOS parity) — the task is created with no list and
    /// appears there because My Tasks shows what is mine or unassigned.
    func testVisibleForMyTasks() {
        XCTAssertTrue(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: true,
                                              isMyTasks: true))
    }

    /// Search and saved-filter lists own no real tasks, so they still have no quick-add.
    func testHiddenForSearchAndSavedFilters() {
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: true))
    }

    func testHiddenWithNoSelection() {
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: false, hasSelection: false))
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: false,
                                               isMyTasks: true), "Not even My Tasks without a selection")
    }

    // MARK: - Focus (Task b71850e6)

    /// THE BUG: `addFieldFocused` was bound to the field and never set by anything, so the bar
    /// could only take focus from a direct click — "add task didn't always have a cursor prompt".
    func testTakesFocusWhenTheBarIsShownForARealList() {
        XCTAssertTrue(MacAddTaskBar.shouldTakeFocus(isVisible: true, isSearchActive: false))
    }

    /// A hidden bar must not grab the caret — there is no field on screen to put it in.
    func testDoesNotTakeFocusWhenHidden() {
        XCTAssertFalse(MacAddTaskBar.shouldTakeFocus(isVisible: false, isSearchActive: false))
    }

    /// The one case that must NOT steal focus: typing a search query has to stay in the search
    /// field. A quick-add that grabs the caret mid-search is worse than one that never focuses.
    func testDoesNotStealFocusFromSearch() {
        XCTAssertFalse(MacAddTaskBar.shouldTakeFocus(isVisible: true, isSearchActive: true),
                       "focus jumped out of the search field and into quick-add")
    }

    /// Adding several tasks in a row is the common case, so the caret stays put after a commit
    /// rather than making you click back in each time.
    func testKeepsFocusAfterAddingATask() {
        XCTAssertTrue(MacAddTaskBar.retainsFocusAfterCommit)
    }

    // MARK: - Placement (AITD-300)

    /// "[MAC] move Add a task to top of the list (not bottom)". The bar used to be the last thing
    /// in the list column, below every row; on a desktop the place you add is the top, where the
    /// eye starts and where the newest work sits. The placement is a rule so a layout refactor
    /// cannot quietly drop it back to the bottom.
    func testAITD300_QuickAddSitsAtTheTopOfTheList() {
        XCTAssertEqual(MacAddTaskBar.placement, .top)
    }
}
#endif
