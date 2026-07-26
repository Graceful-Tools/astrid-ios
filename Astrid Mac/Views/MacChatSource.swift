//  MacChatSource.swift
//  Astrid for Mac — what a chat panel is talking to (task 51703e2a).
//
//  My Tasks is a VIRTUAL list, so it has no list id — but it does have a chat channel: iOS
//  (ChatPanelView) and web (useListChatChannel) both resolve one from a virtual key, and the v1
//  API has accepted `virtualKey` all along. Mac was the only client that hid chat there, because
//  its panel required a real list id.
//
//  Keeping the key format in one pure place is what makes Mac land in the SAME channel as the
//  other clients rather than creating a parallel one.

#if os(macOS)
import Foundation

enum MacChatSource: Equatable {
    case list(String)          // a real list's channel
    case virtual(String)       // a virtual list's channel, e.g. My Tasks

    /// The virtual key iOS and web use: `virtual-chat:<userId>:<virtualListType>`.
    /// Must match ChatPanelView.swift (iOS) and use-list-chat-channel.ts (web) exactly.
    static func virtualKey(userId: String, virtualListType: String) -> String {
        "virtual-chat:\(userId):\(virtualListType)"
    }

    /// The chat source for a Mac selection, or nil when the selection has no channel
    /// (Search, or a saved-filter list, or nothing selected).
    static func forSelection(selectedListId: String?, myTasksId: String, searchId: String,
                             isRealList: Bool, userId: String?) -> MacChatSource? {
        guard let selectedListId else { return nil }
        if selectedListId == myTasksId {
            guard let userId, !userId.isEmpty else { return nil }
            return .virtual(virtualKey(userId: userId, virtualListType: "my-tasks"))
        }
        if selectedListId == searchId { return nil }
        return isRealList ? .list(selectedListId) : nil
    }

    /// Real lists have members to @mention; a virtual channel has none to fetch.
    var listIdForMembers: String? {
        if case .list(let id) = self { return id }
        return nil
    }
}
#endif
