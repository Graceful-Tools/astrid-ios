//  MacLaunchSelectionTests.swift
//  Where the Mac shell opens.
//
//  The selection lives in @SceneStorage, so the app reopened on whatever list
//  was last showing. That is a reasonable restore and a poor landing: the saved
//  id can name a list since deleted, left, or unshared, and the shell then opens
//  on an empty pane with nothing explaining why.

import XCTest
@testable import Astrid_Mac

final class MacLaunchSelectionTests: XCTestCase {

    private let myTasks = "__mytasks__"

    /// THE ASK: opening the app with a session lands on My Tasks — and so does
    /// signing in, since the shell is built fresh in both cases.
    func testTheShellLandsOnMyTasks() {
        XCTAssertEqual(MacLaunchSelection.landingListId(restored: nil, myTasksId: myTasks),
                       myTasks)
    }

    /// A saved selection does NOT win. Pinned rather than left as an absence,
    /// because reinstating the restore would look like a fix.
    func testASavedSelectionDoesNotOverrideMyTasks() {
        XCTAssertEqual(MacLaunchSelection.landingListId(restored: "some-list-id",
                                                        myTasksId: myTasks),
                       myTasks)
    }

    /// Including one that no longer exists — the case that motivated this.
    func testAStaleSavedSelectionCannotStrandTheShell() {
        XCTAssertEqual(MacLaunchSelection.landingListId(restored: "deleted-list-42",
                                                        myTasksId: myTasks),
                       myTasks)
    }

    /// It always answers with something, so the shell never opens with no
    /// selection at all.
    func testItAlwaysProducesASelection() {
        for restored in [nil, "", "a-list"] as [String?] {
            XCTAssertFalse(MacLaunchSelection.landingListId(restored: restored,
                                                            myTasksId: myTasks).isEmpty)
        }
    }
}
