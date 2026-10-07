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

    // MARK: AWTD2-67 — an agent's chat avatar is its own mark, not the generic sparkles badge

    /// The exact payload the list chat carries for a Claude message (as the server sends it).
    private let claude = User(id: "ai-agent-claude", email: "claude@astrid.cc", name: "Claude Agent",
                              image: "https://uvq3rbgqrtvvavdq.public.blob.vercel-storage.com/ai-agents/claude.png",
                              isAIAgent: true, aiAgentType: "claude_agent")

    func testAWTD2_67_claudeChatAvatarIsTheClaudeMark() {
        XCTAssertEqual(MacChatBubbleStyle.avatar(author: claude, isAgent: true), .brandMark("ai-claude"),
                       "Claude drew a purple sparkles circle in Mac chat instead of its mark")
    }

    func testAWTD2_67_agentWithoutABundledMarkUsesItsPhoto() {
        let custom = User(id: "a1", email: "helper@agents.example", name: "Helper",
                          image: "https://img/helper.png", isAIAgent: true, aiAgentType: "custom_agent")
        XCTAssertEqual(MacChatBubbleStyle.avatar(author: custom, isAgent: true), .photo("https://img/helper.png"))
    }

    func testAWTD2_67_agentWithNothingKeepsTheBadge() {
        let bare = User(id: "a2", email: nil, name: "Agent", image: nil, isAIAgent: true, aiAgentType: nil)
        XCTAssertEqual(MacChatBubbleStyle.avatar(author: bare, isAgent: true), .agentBadge)
        XCTAssertEqual(MacChatBubbleStyle.avatar(author: nil, isAgent: true), .agentBadge)
    }

    func testAWTD2_67_peopleGetTheirPhotoOrInitials() {
        let ada = User(id: "u2", email: "ada@example.com", name: "Ada Lovelace", image: "https://img/ada.png")
        XCTAssertEqual(MacChatBubbleStyle.avatar(author: ada, isAgent: false), .photo(ada.cachedImageURL!))
        XCTAssertEqual(MacChatBubbleStyle.avatar(author: nil, isAgent: false), .initials("?"))
    }
}
#endif
