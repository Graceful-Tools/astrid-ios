//  ReplyHandBackTests.swift
//  ADEV-360: answering a question left the task assigned to you; "Hand back" returns it to the
//  asker in one tap, and an agent gets it in Ready so its queue actually picks it up.

import XCTest
@testable import Astrid_App

final class ReplyHandBackTests: XCTestCase {

    private let me = "me"
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func comment(_ id: String, by authorId: String?, name: String? = nil, agent: Bool = false,
                         at offset: TimeInterval) -> Comment {
        var author: User?
        if let authorId {
            var u = User(id: authorId, email: nil, name: name, image: nil)
            u.isAIAgent = agent
            author = u
        }
        return Comment(id: id, content: "c", type: .TEXT, authorId: authorId, author: author,
                       taskId: "t1", createdAt: t0.addingTimeInterval(offset), updatedAt: nil)
    }

    private var agentAsked: [Comment] {
        [comment("q", by: "ai-agent-claude", name: "Claude Agent", agent: true, at: 0),
         comment("s", by: nil, at: 5),
         comment("a", by: me, name: "Jon", at: 10)]
    }

    func testADEV360_anAgentsQuestionIsHandedBackToTheAgentInReady() {
        let target = ReplyHandBack.target(assigneeId: me, currentUserId: me, completed: false,
                                          comments: agentAsked)
        XCTAssertEqual(target, .init(userId: "ai-agent-claude", name: "Claude Agent", isAgent: true))
        XCTAssertEqual(target?.statusRole, "ready")
    }

    func testADEV360_aPersonGetsItBackWithoutAColumnChange() {
        let comments = [comment("q", by: "sam", name: "Sam", at: 0), comment("a", by: me, at: 10)]
        let target = ReplyHandBack.target(assigneeId: me, currentUserId: me, completed: false,
                                          comments: comments)
        XCTAssertEqual(target?.userId, "sam")
        XCTAssertNil(target?.statusRole)
    }

    func testADEV360_theNewestOtherAuthorIsTheAsker() {
        let comments = [comment("late", by: "sam", name: "Sam", at: 20),
                        comment("early", by: "ai-agent-claude", agent: true, at: 0)]
        XCTAssertEqual(ReplyHandBack.target(assigneeId: me, currentUserId: me, completed: false,
                                            comments: comments)?.userId, "sam")
    }

    func testADEV360_notOfferedOnSomeoneElsesTaskOrADoneOne() {
        XCTAssertNil(ReplyHandBack.target(assigneeId: "sam", currentUserId: me, completed: false,
                                          comments: agentAsked))
        XCTAssertNil(ReplyHandBack.target(assigneeId: me, currentUserId: me, completed: true,
                                          comments: agentAsked))
        XCTAssertNil(ReplyHandBack.target(assigneeId: nil, currentUserId: nil, completed: false,
                                          comments: agentAsked))
    }

    func testADEV360_notOfferedWhenOnlyYouAndTheSystemHaveSpoken() {
        let comments = [comment("s", by: nil, at: 0), comment("a", by: me, at: 10)]
        XCTAssertNil(ReplyHandBack.target(assigneeId: me, currentUserId: me, completed: false,
                                          comments: comments))
    }

    // Jon on ADEV-360: "The ui is text but we want a button on all platform. Kind of like
    // 'send & Archive' with Gmail." One blue button posts the reply AND hands the task back; its
    // words say exactly what the tap will do.
    func testADEV360_theButtonSaysWhatOneTapDoes() {
        let agent = ReplyHandBack.Target(userId: "a", name: "Claude Agent", isAgent: true)
        let person = ReplyHandBack.Target(userId: "p", name: "Sam", isAgent: false)
        XCTAssertEqual(ReplyHandBack.titleKey(for: agent, hasReply: true), "comments.reply_reassign_ready")
        XCTAssertEqual(ReplyHandBack.titleKey(for: agent, hasReply: false), "comments.reassign_ready")
        XCTAssertEqual(ReplyHandBack.titleKey(for: person, hasReply: true), "comments.reply_reassign")
        XCTAssertEqual(ReplyHandBack.titleKey(for: person, hasReply: false), "comments.reassign")
        for key in ["comments.reply_reassign_ready", "comments.reassign_ready", "comments.reply_reassign",
                    "comments.reassign", "comments.hand_back_to"] {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, "\(key) is in Localizable.strings")
        }
    }

    @MainActor
    func testADEV360_replyIsPostedBeforeTheHandBack() async throws {
        var order: [String] = []
        let target = ReplyHandBack.Target(userId: "a", name: "Claude Agent", isAgent: true)
        try await ReplyHandBack.replyThenHandBack(target, reply: { order.append("reply") },
                                                  handBack: { t in order.append("handBack \(t.userId) \(t.statusRole ?? "-")") })
        XCTAssertEqual(order, ["reply", "handBack a ready"])

        order = []
        try await ReplyHandBack.replyThenHandBack(target, reply: nil, handBack: { _ in order.append("handBack") })
        XCTAssertEqual(order, ["handBack"], "nothing typed: just the hand-back")
    }
}
