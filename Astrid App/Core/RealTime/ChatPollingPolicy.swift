//  ChatPollingPolicy.swift
//  When the chat panel's fallback poll should run — pure, so the rule is testable without a
//  socket or a timer. Sibling of `SSEReconnectPolicy`.
//
//  The panel used to start this poll from `loadChannel` unconditionally and describe it as an
//  "SSE backup", but nothing gated it on the stream being down. It is a backup now.
import Foundation

enum ChatPollingPolicy {
    /// How often the fallback refetches while it is running.
    nonisolated static let interval: TimeInterval = 3.0

    /// A live stream already delivers created/updated/deleted, so polling on top of it is pure
    /// duplication. Without a resolved channel or a session there is nothing to fetch at all —
    /// checked here rather than inside the timer body, so the timer does not wake up 20 times a
    /// minute to decide to do nothing.
    nonisolated static func shouldPoll(isStreamLive: Bool, hasChannel: Bool, isAuthenticated: Bool) -> Bool {
        guard hasChannel, isAuthenticated else { return false }
        return !isStreamLive
    }
}
