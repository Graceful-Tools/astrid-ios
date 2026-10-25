//  MacOneHeaderTests.swift
//  AITD-553: "[mac] there should be only one HEADER on the mac and buttons should open the
//  settings (no arrow to get another list)".
//
//  The list had THREE strips of controls: the window toolbar (list/board picker, sort, gear), a
//  strip above the rows holding the filter button, and on a board a third strip with a "⋯" whose
//  only item was Disable Board. Both buttons opened a one-line menu before you got to what they
//  were for — the gear a List Settings / Remove Favorite / Enable Board menu, sort a "Sort ›"
//  submenu.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacOneHeaderTests: XCTestCase {

    private let owner = "u-owner"
    private let member = "u-member"

    private func list(projectId: String? = nil) -> TaskList {
        var l = TaskList(id: "l1", name: "Work")
        l.ownerId = owner
        l.listMembers = [ListMember(id: "m-member", listId: "l1", userId: member, role: "member")]
        l.projectId = projectId
        return l
    }

    // MARK: one header

    /// "make the toggle separate from the sort/settings/filter button bar" — and then "remove the
    /// separate filter menu on lists since there is a filter tab in the settings menu". A real
    /// list's filters are List Settings ▸ Filters, which the gear opens.
    func testARealListsHeaderIsThePickerThenSortAndSettings_AITD553() {
        XCTAssertEqual(MacListChrome.titleBarGroups(showsModePicker: true, hasSelection: true,
                                                    isRealList: true, isMyTasks: false, isListMode: true),
                       [[.modePicker], [.sort, .listSettings]])
        XCTAssertFalse(MacListChrome.realListHasFilterButton)
    }

    /// My Tasks has its own filter (account preferences) and no list settings.
    func testMyTasksHeaderCarriesItsOwnFilter_AITD553() {
        XCTAssertEqual(MacListChrome.titleBarGroups(showsModePicker: false, hasSelection: true,
                                                    isRealList: false, isMyTasks: true, isListMode: true),
                       [[.sort, .myTasksFilter]])
    }

    /// A board has no rows to sort or filter; the gear is still there, apart from the picker.
    func testABoardsHeaderIsThePickerAndTheGear_AITD553() {
        XCTAssertEqual(MacListChrome.titleBarGroups(showsModePicker: true, hasSelection: true,
                                                    isRealList: true, isMyTasks: false, isListMode: false),
                       [[.modePicker], [.listSettings]])
    }

    /// Nothing selected, nothing in the header — and no empty group to draw a stray capsule.
    func testNoSelectionDrawsNoGroups_AITD553() {
        XCTAssertEqual(MacListChrome.titleBarGroups(showsModePicker: false, hasSelection: false,
                                                    isRealList: false, isMyTasks: false, isListMode: true),
                       [])
    }

    /// The strip above the rows is gone: every control it held is in the header now.
    func testTheListColumnHasNoSecondHeader_AITD553() {
        XCTAssertFalse(MacListChrome.listColumnHasStrip)
        XCTAssertFalse(MacBoardView.hasHeaderStrip, "the board's own ⋯ strip goes too")
    }

    // MARK: the gear opens the window

    /// "tapping the button should just open the lists settings (shouldn't have this intermediate
    /// drop down list)". Favorite and the board switch the menu held move INTO the window.
    func testTheGearOpensSettingsDirectly_AITD553() {
        XCTAssertFalse(MacListSettingsButton.isMenu)
    }

    /// Favourite is a personal preference, so it sits with the other personal settings.
    func testFavoriteIsInTheSortAndFiltersTab_AITD553() {
        XCTAssertEqual(MacListSettingsWindow.tab(for: .favorite), .sortFilters)
    }

    /// Enable / Disable Board changes the list for everyone: Admin, as on iOS's ListAdminTab.
    func testTheBoardSwitchIsInTheAdminTab_AITD553() {
        XCTAssertEqual(MacListSettingsWindow.tab(for: .board), .admin)
        XCTAssertTrue(MacListAdminTab.offersBoardSwitch(for: list(), userId: owner))
        XCTAssertFalse(MacListAdminTab.offersBoardSwitch(for: list(), userId: member))
    }

    /// The button names what the click will DO.
    func testTheBoardSwitchLabelFlipsWithTheList_AITD553() {
        XCTAssertEqual(MacListAdminTab.boardSwitchLabelKey(hasBoard: false), "mac.enable_board")
        XCTAssertEqual(MacListAdminTab.boardSwitchLabelKey(hasBoard: true), "mac.disable_board")
    }

    // MARK: sort without a submenu

    /// "don't show this sub menu! just go directly to the sort menu". A Picker inside a Menu is
    /// drawn as a "Sort ›" submenu unless it is inline.
    func testSortOptionsAreInlineInTheMenu_AITD553() {
        XCTAssertTrue(MacSortMenu.optionsInline)
    }

    // MARK: popovers, sized to the screen (AITD-553 follow-up)

    /// "tapping out of the filter menu should dismiss the menu vs just the done button" — a
    /// popover closes on a click outside it; a sheet does not. Same for List Settings.
    func testFilterAndSettingsAreTransientPopovers_AITD553() {
        XCTAssertTrue(MacListChrome.filterAndSettingsArePopovers)
    }

    /// "make it wider if the screen can accommodate": the filter popover grows with the screen,
    /// between the old 340 and a width past which rows only get emptier.
    func testTheFilterPopoverWidensWithTheScreen_AITD553() {
        XCTAssertEqual(MacListChrome.filterPopoverWidth(screenWidth: 1000), 400)
        XCTAssertEqual(MacListChrome.filterPopoverWidth(screenWidth: 700), 340, "never narrower than before")
        XCTAssertEqual(MacListChrome.filterPopoverWidth(screenWidth: 3000), 520, "capped")
    }

    /// List Settings likewise, and tall enough that the Filters tab never scrolls; it shrinks
    /// only on a screen too short to hold it.
    func testTheSettingsPopoverSizesToTheScreen_AITD553() {
        let roomy = MacListChrome.settingsPopoverSize(screen: CGSize(width: 1800, height: 1100))
        XCTAssertEqual(roomy.width, 640)
        XCTAssertEqual(roomy.height, MacListChrome.settingsPopoverMaxHeight)
        XCTAssertGreaterThanOrEqual(MacListChrome.settingsPopoverMaxHeight,
                                    MacListChrome.filtersTabNeededHeight, "the Filters tab fits without scrolling")

        let small = MacListChrome.settingsPopoverSize(screen: CGSize(width: 1000, height: 600))
        XCTAssertEqual(small.width, 460, "never narrower than the old window")
        XCTAssertEqual(small.height, 600 - MacListChrome.settingsPopoverScreenMargin)
    }
}
#endif
