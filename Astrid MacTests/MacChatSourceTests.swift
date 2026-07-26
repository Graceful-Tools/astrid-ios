//  MacChatSourceTests.swift
//  Regression for task 51703e2a — "[Mac] add list messages to My Tasks".
//
//  My Tasks has a chat channel on iOS (ChatPanelView) and web (use-list-chat-channel), resolved
//  from a VIRTUAL key; the v1 API has accepted `virtualKey` all along. Mac hid chat there because
//  its panel demanded a real list id. The key format is the contract — get it wrong and Mac lands
//  in a different channel from the other clients instead of the same conversation.

import XCTest
@testable import Astrid_Mac

final class MacChatSourceTests: XCTestCase {

    private let myTasks = "__my_tasks__"
    private let search = "__search__"

    func testMyTasksResolvesTheVirtualChannel() {
        let source = MacChatSource.forSelection(selectedListId: myTasks, myTasksId: myTasks,
                                                searchId: search, isRealList: false, userId: "user-1")
        XCTAssertEqual(source, .virtual("virtual-chat:user-1:my-tasks"))
    }

    /// The exact string iOS builds in ChatPanelView and web builds in use-list-chat-channel.
    func testVirtualKeyFormatMatchesTheOtherClients() {
        XCTAssertEqual(MacChatSource.virtualKey(userId: "abc", virtualListType: "my-tasks"),
                       "virtual-chat:abc:my-tasks")
    }

    func testRealListUsesItsOwnChannel() {
        let source = MacChatSource.forSelection(selectedListId: "list-9", myTasksId: myTasks,
                                                searchId: search, isRealList: true, userId: "user-1")
        XCTAssertEqual(source, .list("list-9"))
    }

    func testSearchHasNoChannel() {
        XCTAssertNil(MacChatSource.forSelection(selectedListId: search, myTasksId: myTasks,
                                                searchId: search, isRealList: false, userId: "user-1"))
    }

    /// A saved-filter (virtual, non-My-Tasks) list owns no channel.
    func testSavedFilterListHasNoChannel() {
        XCTAssertNil(MacChatSource.forSelection(selectedListId: "filter-1", myTasksId: myTasks,
                                                searchId: search, isRealList: false, userId: "user-1"))
    }

    func testNoSelectionHasNoChannel() {
        XCTAssertNil(MacChatSource.forSelection(selectedListId: nil, myTasksId: myTasks,
                                                searchId: search, isRealList: false, userId: "user-1"))
    }

    /// Signed out (or before the session resolves) there is no user to key the channel on — and a
    /// key like "virtual-chat::my-tasks" would be a shared bucket across users.
    func testMyTasksWithoutAUserIdHasNoChannel() {
        XCTAssertNil(MacChatSource.forSelection(selectedListId: myTasks, myTasksId: myTasks,
                                                searchId: search, isRealList: false, userId: nil))
        XCTAssertNil(MacChatSource.forSelection(selectedListId: myTasks, myTasksId: myTasks,
                                                searchId: search, isRealList: false, userId: ""))
    }

    func testOnlyRealListsExposeMembersToMention() {
        XCTAssertEqual(MacChatSource.list("list-9").listIdForMembers, "list-9")
        XCTAssertNil(MacChatSource.virtual("virtual-chat:u:my-tasks").listIdForMembers)
    }
}
