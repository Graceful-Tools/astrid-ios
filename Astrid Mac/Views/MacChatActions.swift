//  MacChatActions.swift
//  Astrid for Mac — pure permission helper for chat message actions (Task 021e5b93).

#if os(macOS)
import Foundation

enum MacChatActions {
    /// You can delete only your own (non-system, non-pending) messages — matches iOS/web.
    static func canDelete(authorId: String?, currentUserId: String?, isPending: Bool) -> Bool {
        guard !isPending, let authorId, let currentUserId else { return false }
        return authorId == currentUserId
    }
}
#endif
