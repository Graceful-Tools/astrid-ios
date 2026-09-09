//  MacListMenuTests.swift
//  Astrid for Mac — AITD-373: the list settings menu, wherever a list is drawn.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListMenuTests: XCTestCase {

    private let owner = "u-owner"
    private let admin = "u-admin"
    private let member = "u-member"

    /// Roles come from `listMembers`, which is what `TaskList.role(for:)` reads — the `admins` /
    /// `members` User arrays are display rosters and do not decide permission.
    private func list(projectId: String? = nil, isFavorite: Bool? = nil) -> TaskList {
        var l = TaskList(id: "l1", name: "Work")
        l.ownerId = owner
        l.listMembers = [
            ListMember(id: "m-admin", listId: "l1", userId: admin, role: "admin"),
            ListMember(id: "m-member", listId: "l1", userId: member, role: "member"),
        ]
        l.projectId = projectId
        l.isFavorite = isFavorite
        return l
    }

    // MARK: - Who sees what

    /// The owner sees everything, Delete included.
    func testOwnerSeesEveryItem_AITD373() {
        let items = MacListMenu.items(for: list(), userId: owner)
        XCTAssertEqual(items, [.edit, .toggleFavorite, .sharing, .enableBoard, .divider, .delete])
    }

    /// An admin may reconfigure the list but not destroy it — deleting a shared list destroys
    /// other people's work, so it stays with the owner. Same split ListPermissions draws.
    func testAdminSeesEverythingButDelete_AITD373() {
        let items = MacListMenu.items(for: list(), userId: admin)
        XCTAssertTrue(items.contains(.edit))
        XCTAssertTrue(items.contains(.sharing))
        XCTAssertFalse(items.contains(.delete))
        XCTAssertFalse(items.contains(.divider), "no divider with nothing behind it")
    }

    /// A plain member gets Favourite and nothing else. Favouriting is a personal view preference,
    /// not a change to the list, so it survives where Edit and Sharing do not.
    func testAPlainMemberSeesOnlyFavourite_AITD373() {
        XCTAssertEqual(MacListMenu.items(for: list(), userId: member), [.toggleFavorite])
    }

    /// Signed out, or looking at someone else's public list: nothing but the personal preference.
    func testAStrangerSeesOnlyFavourite_AITD373() {
        XCTAssertEqual(MacListMenu.items(for: list(), userId: nil), [.toggleFavorite])
    }

    // MARK: - Enable board

    /// A list that is already a project board has nothing to enable.
    func testEnableBoardIsHiddenOnceTheListIsABoard_AITD373() {
        let items = MacListMenu.items(for: list(projectId: "p1"), userId: owner)
        XCTAssertFalse(items.contains(.enableBoard))
        XCTAssertTrue(items.contains(.edit), "the rest of the menu is unaffected")
    }

    // MARK: - Labels

    func testFavouriteLabelFlipsWithTheList() {
        XCTAssertEqual(MacListMenu.favoriteLabelKey(isFavorite: false), "lists.favorite")
        XCTAssertEqual(MacListMenu.favoriteLabelKey(isFavorite: true), "mac.remove_favorite")
    }

    // MARK: - Where it is offered

    /// The point of the task. A board offered NO route to list settings — its whole chrome strip
    /// was suppressed, because sort and filter both require list mode. The settings menu is not
    /// a sorted-rows control, so it belongs there too.
    func testABoardOffersTheListMenu_AITD373() {
        XCTAssertTrue(MacListChrome.showsListMenu(isRealList: true, isListMode: false))
    }

    /// My Tasks is virtual and owns no TaskList — there are no settings to open.
    func testAVirtualSelectionOffersNoListMenu_AITD373() {
        XCTAssertFalse(MacListChrome.showsListMenu(isRealList: false, isListMode: false))
    }

    /// List mode keeps the menu in the sidebar's right-click, where it has always been, rather
    /// than gaining a third control beside sort and filter (Jon asked for the board).
    func testListModeStripDoesNotGainTheMenu_AITD373() {
        XCTAssertFalse(MacListChrome.showsListMenu(isRealList: true, isListMode: true))
    }
}
#endif
