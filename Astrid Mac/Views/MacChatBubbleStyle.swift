//  MacChatBubbleStyle.swift
//  Astrid for Mac — pure styling rules for chat bubbles (Task eb1b7da6), mirroring iOS
//  ChatMessageBubble: my messages right-aligned in accent, agents in purple with a sparkles
//  badge, others left-aligned on the theme surface.

#if os(macOS)
import SwiftUI

enum MacChatBubbleStyle {
    static func isMine(authorId: String?, currentUserId: String?) -> Bool {
        guard let authorId, let currentUserId else { return false }
        return authorId == currentUserId
    }

    /// Bubble fill: mine = accent tint; agent = purple tint; others = theme card.
    static func fill(isMine: Bool, isAgent: Bool) -> Color {
        if isAgent { return Color.purple.opacity(0.14) }
        if isMine { return Theme.accent.opacity(0.16) }
        return Theme.bgSecondary
    }

    static func alignment(isMine: Bool) -> HorizontalAlignment { isMine ? .trailing : .leading }
    static func showsAvatar(isMine: Bool) -> Bool { !isMine }   // avatars only on others' messages
}
#endif
