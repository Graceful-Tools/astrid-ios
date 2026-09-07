//  MacSystemComments.swift
//  Astrid for Mac — hiding status chatter in the comment thread (Task 9c24d16c).
//
//  A comment with no author is the system talking ("marked complete", "moved to …"). iOS
//  (CommentSectionViewEnhanced) hides those by default and offers a toggle only when there are
//  any; the Mac showed every one of them, always, burying the actual conversation.
//
//  The RULE itself lives in `Core/Tasks/CommentVisibility.swift` and is shared with iOS
//  (ASTRID.md §9: Mac adds no business logic). This file used to restate it — `isSystem`,
//  `displayed` and `count` were reimplemented here, and the Mac `isSystem` had already lost the
//  offline guard that the shared one carries. Only the toggle's PRESENTATION is Mac's own
//  (task 41abea5f / AITD-318).
//
//  The offline exception is worth knowing while reading this: cached comments can come back
//  WITHOUT an authorId, so filtering while disconnected would empty the thread — a much worse
//  failure than showing a few status lines.

#if os(macOS)
import Foundation

enum MacSystemComments {

    /// No system comments (or offline, where they are all shown anyway) → no toggle: an affordance
    /// that reveals nothing is noise.
    ///
    /// The `!isOffline` short-circuit is doing real work here — offline, EVERY cached comment can
    /// look authorless, so the shared `isSystem` returns false and the toggle would be pointless
    /// even if we asked.
    static func showsToggle(_ comments: [Comment], isOffline: Bool) -> Bool {
        !isOffline && comments.contains {
            CommentVisibility.isSystem(authorId: $0.authorId, isOffline: isOffline)
        }
    }

    static func toggleTitle(showingSystem: Bool) -> String {
        NSLocalizedString(showingSystem ? "mac.system_comments_hide" : "mac.system_comments_show",
                          comment: "")
    }
}

/// The other half of the rule above: what the Mac must SEND so its own comments survive it.
///
/// A comment posted without an authorId is filtered straight back out of the thread — the comment
/// you just typed disappears until the Outbox syncs and a refresh returns the server copy, which
/// does carry an author (task a3f868b4).
enum MacCommentPost {
    /// The author a comment posted from this Mac must carry.
    static func authorId(currentUserId: String?) -> String? { currentUserId }

    /// Whether a comment posted with this author will actually be visible in the thread.
    ///
    /// Asks the shared rule rather than restating `authorId != nil`, so this cannot start
    /// disagreeing with the filter it exists to predict (AITD-318). Online is the case that
    /// matters: offline nothing is filtered, so a post is visible either way.
    static func isVisibleInThread(authorId: String?) -> Bool {
        !CommentVisibility.isSystem(authorId: authorId, isOffline: false)
    }
}
#endif
