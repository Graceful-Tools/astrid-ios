//  MacChatBubbleStyleTests.swift
//  Astrid for Mac — Task eb1b7da6: chat bubble styling rules (mine/agent/others).

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacChatBubbleStyleTests: XCTestCase {

    func testIsMine() {
        XCTAssertTrue(MacChatBubbleStyle.isMine(authorId: "u1", currentUserId: "u1"))
        XCTAssertFalse(MacChatBubbleStyle.isMine(authorId: "u2", currentUserId: "u1"))
        XCTAssertFalse(MacChatBubbleStyle.isMine(authorId: nil, currentUserId: "u1"))   // system msg
        XCTAssertFalse(MacChatBubbleStyle.isMine(authorId: "u1", currentUserId: nil))   // signed out
    }

    func testFillsAreDistinct() {
        let mine = MacChatBubbleStyle.fill(isMine: true, isAgent: false)
        let agent = MacChatBubbleStyle.fill(isMine: false, isAgent: true)
        let other = MacChatBubbleStyle.fill(isMine: false, isAgent: false)
        XCTAssertNotEqual(mine, other, "My bubbles must be visually distinct")
        XCTAssertNotEqual(agent, other, "Agent bubbles must be visually distinct (purple)")
        XCTAssertNotEqual(agent, mine)
        // Agent styling wins even if the agent were 'me'.
        XCTAssertEqual(MacChatBubbleStyle.fill(isMine: true, isAgent: true), agent)
    }

    func testAlignmentAndAvatars() {
        XCTAssertEqual(MacChatBubbleStyle.alignment(isMine: true), .trailing)
        XCTAssertEqual(MacChatBubbleStyle.alignment(isMine: false), .leading)
        XCTAssertFalse(MacChatBubbleStyle.showsAvatar(isMine: true), "No avatar on my own messages")
        XCTAssertTrue(MacChatBubbleStyle.showsAvatar(isMine: false))
    }
}
#endif
