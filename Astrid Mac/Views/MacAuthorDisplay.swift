//  MacAuthorDisplay.swift
//  Astrid for Mac — who wrote this, and what to show for them (Task 283a03df).
//
//  Three surfaces rendered an author and each did it differently. The detail bubble asked whether
//  the author was you but drew initials only, never a photo. The board editor and the chat panel
//  never asked at all, so they read `author?.name ?? "Someone"` — and a comment you have just
//  posted carries `authorId` with no embedded `author`, which is precisely the case that produced
//  your own words attributed to a stranger.
//
//  One decision for all three, mirroring iOS CommentRowViewEnhanced: you resolve through the
//  cached session (no fetch needed for yourself), everyone else through the payload.

#if os(macOS)
import Foundation

struct MacAuthorDisplay: Equatable {
    let isCurrentUser: Bool
    let name: String
    let imageURL: String?
    let initials: String

    static func of(authorId: String?, author: User?, currentUser: User?) -> MacAuthorDisplay {
        // A system comment carries no authorId by design, so "no id" can never mean "me".
        if let authorId, let currentUser, authorId == currentUser.id {
            return MacAuthorDisplay(isCurrentUser: true,
                                    name: NSLocalizedString("assignee.you", comment: ""),
                                    imageURL: currentUser.cachedImageURL,
                                    initials: currentUser.initials)
        }
        if let author {
            return MacAuthorDisplay(isCurrentUser: false,
                                    name: author.displayName,
                                    imageURL: author.cachedImageURL,
                                    initials: author.initials)
        }
        return MacAuthorDisplay(isCurrentUser: false,
                                name: NSLocalizedString("mac.unknown_author", comment: ""),
                                imageURL: nil,
                                initials: "?")
    }

    /// Convenience for a comment.
    static func of(_ comment: Comment, currentUser: User?) -> MacAuthorDisplay {
        of(authorId: comment.authorId, author: comment.author, currentUser: currentUser)
    }
}
#endif
