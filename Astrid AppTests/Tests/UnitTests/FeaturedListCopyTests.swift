//  FeaturedListCopyTests.swift
//  Task AITD-348 — the featured-list "Copy List" button copied nothing.
//
//  `TaskListView.copyList()` was:
//
//      private func copyList() async {
//          guard let _ = selectedList else { return }
//          isCopyingList = true
//          // TODO: Implement copy list API v1 endpoint
//          do { isCopyingList = false }
//      }
//
//  A user-reachable button that showed a spinner for one frame and did nothing. The TODO was
//  stale — `RemoteResourceService.copyList` already existed and the Mac was using it.
//
//  These pin the re-entry rule the button goes through. The source guard that pinned the call
//  site itself was a one-off for this fix and is gone (AITD-532).

import XCTest
@testable import Astrid_App

final class FeaturedListCopyTests: XCTestCase {

    // MARK: - The re-entry rule

    func testACopyStartsWhenAListIsSelectedAndNothingIsInFlight() {
        XCTAssertEqual(FeaturedListCopyPlan.decide(selectedListId: "list-1", isCopying: false),
                       .copy(listId: "list-1"))
    }

    func testASecondTapWhileACopyIsInFlightIsIgnored() {
        // The spinner is the only affordance saying a copy is running, and it is small. Without
        // this the impatient double-tap files the list twice.
        XCTAssertEqual(FeaturedListCopyPlan.decide(selectedListId: "list-1", isCopying: true),
                       .ignore)
    }

    func testNothingHappensWithoutASelectedList() {
        XCTAssertEqual(FeaturedListCopyPlan.decide(selectedListId: nil, isCopying: false), .ignore)
    }

}
