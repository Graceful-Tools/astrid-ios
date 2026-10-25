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

    /// The owner sees everything — which no longer includes Delete (AITD-552).
    ///
    /// `edit` and `sharing` became one `listSettings` item in AITD-388 — two sheets for one
    /// list's settings, with the roster hidden behind whichever you happened to pick.
    func testOwnerSeesEveryItem_AITD373() {
        let items = MacListMenu.items(for: list(), userId: owner)
        XCTAssertEqual(items, [.listSettings, .toggleFavorite, .enableBoard])
    }

    /// An admin may reconfigure the list, the same as the owner in this menu.
    func testAdminSeesTheSameMenuAsTheOwner_AITD373() {
        XCTAssertEqual(MacListMenu.items(for: list(), userId: admin),
                       MacListMenu.items(for: list(), userId: owner))
    }

    // MARK: - Delete lives in Admin (AITD-552)

    /// AITD-552: "Move the 'delete' quick action to the admin." Destroying a list was one click
    /// away in the gear and the sidebar right-click; it is in List Settings ▸ Admin now.
    func testDeleteIsInTheAdminTabNotTheQuickMenu_AITD552() {
        // The menu has no Delete case to offer; the owner's full menu is just these three.
        XCTAssertEqual(MacListMenu.items(for: list(), userId: owner),
                       [.listSettings, .toggleFavorite, .enableBoard])
        XCTAssertTrue(MacListAdminTab.offersDelete(for: list(), userId: owner))
    }

    /// The owner-only rule moves with it: an admin may change every setting but not destroy
    /// other people's work, and a member never sees the Admin tab at all.
    func testOnlyTheOwnerIsOfferedDeleteInAdmin_AITD552() {
        XCTAssertFalse(MacListAdminTab.offersDelete(for: list(), userId: admin))
        XCTAssertFalse(MacListAdminTab.offersDelete(for: list(), userId: member))
        XCTAssertFalse(MacListAdminTab.offersDelete(for: list(), userId: nil))
    }

    /// A plain member now gets List Settings too (AITD-388). The WINDOW decides which tabs they
    /// see — Sort & Filters and Membership, not Admin — and before this they had no route to the
    /// roster at all: they could not see who else was on a list they were on, or leave it.
    func testAPlainMemberSeesListSettingsAndFavourite_AITD388() {
        XCTAssertEqual(MacListMenu.items(for: list(), userId: member),
                       [.listSettings, .toggleFavorite])
    }

    /// Signed out, or looking at someone else's public list. Still no admin items: the window
    /// asks `ListPermissions` for itself, so offering the entry gives nothing away.
    func testAStrangerSeesNoAdminItems_AITD373() {
        let items = MacListMenu.items(for: list(), userId: nil)
        XCTAssertFalse(items.contains(.enableBoard))
    }

    // MARK: - Enable board

    /// A list that is already a project board has nothing to enable.
    func testEnableBoardIsHiddenOnceTheListIsABoard_AITD373() {
        let items = MacListMenu.items(for: list(projectId: "p1"), userId: owner)
        XCTAssertFalse(items.contains(.enableBoard))
        XCTAssertTrue(items.contains(.listSettings), "the rest of the menu is unaffected")
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

    /// AITD-522: "add gear for list settings." List mode gets the menu in its header too — it
    /// used to be reachable only by right-clicking the sidebar row (AITD-373 kept it off).
    func testListModeHeaderOffersTheListMenu_AITD522() {
        XCTAssertTrue(MacListChrome.showsListMenu(isRealList: true, isListMode: true))
    }

    /// AITD-552: the gear sits beside the list/board picker in the window toolbar, in both modes,
    /// and the strip above the rows no longer draws a second one.
    func testTheGearSitsBesideTheModePicker_AITD552() {
        for isListMode in [true, false] {
            XCTAssertTrue(MacListChrome.titleBarShowsListMenu(isRealList: true, isListMode: isListMode))
            XCTAssertFalse(MacListChrome.stripShowsListMenu(isRealList: true, isListMode: isListMode))
        }
        XCTAssertFalse(MacListChrome.titleBarShowsListMenu(isRealList: false, isListMode: true),
                       "My Tasks owns no list settings")
    }

    /// …behind a gear, the Mac's settings glyph, rather than the sliders that read as filters.
    func testTheListSettingsButtonIsAGear_AITD522() {
        XCTAssertEqual(MacListSettingsButton.symbol, "gearshape")
    }
}
#endif
