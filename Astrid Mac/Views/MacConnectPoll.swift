//  MacConnectPoll.swift
//  Thin alias for the shared `ConnectionPoll` in Core (AITD-362). The predicate used to live
//  here, which is how iOS ended up without one at all — keep the Mac call sites working while
//  the single copy lives next to the services that poll.
#if os(macOS)
import Foundation

enum MacConnectPoll {
    static let maxAttempts = ConnectionPoll.maxAttempts
    static let intervalNanos = ConnectionPoll.intervalNanos

    /// Keep polling while not yet connected and under the attempt cap.
    static func shouldContinue(attempt: Int, connected: Bool,
                               maxAttempts: Int = ConnectionPoll.maxAttempts) -> Bool {
        ConnectionPoll.shouldContinue(attempt: attempt, connected: connected, maxAttempts: maxAttempts)
    }
}
#endif
