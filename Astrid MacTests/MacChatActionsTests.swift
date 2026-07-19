//  MacChatActionsTests.swift
//  Astrid for Mac — Task 021e5b93: you may delete only your own, non-pending chat messages.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacChatActionsTests: XCTestCase {

    func testCanDeleteOwnMessage() {
        XCTAssertTrue(MacChatActions.canDelete(authorId: "me", currentUserId: "me", isPending: false))
    }

    func testCannotDeleteOthers() {
        XCTAssertFalse(MacChatActions.canDelete(authorId: "them", currentUserId: "me", isPending: false))
    }

    func testCannotDeletePendingOrSystem() {
        XCTAssertFalse(MacChatActions.canDelete(authorId: "me", currentUserId: "me", isPending: true))
        XCTAssertFalse(MacChatActions.canDelete(authorId: nil, currentUserId: "me", isPending: false))
        XCTAssertFalse(MacChatActions.canDelete(authorId: "me", currentUserId: nil, isPending: false))
    }
}
#endif
