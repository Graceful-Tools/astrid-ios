//  MacConnectPoll.swift
//  Astrid for Mac — pure poll-loop rule for OAuth connect (no in-app callback on macOS, so we poll
//  the connection status after opening the browser instead of forcing a close/reopen).

#if os(macOS)
import Foundation

enum MacConnectPoll {
    static let maxAttempts = 20      // ~40s at 2s intervals
    static let intervalNanos: UInt64 = 2_000_000_000

    /// Keep polling while not yet connected and under the attempt cap.
    static func shouldContinue(attempt: Int, connected: Bool, maxAttempts: Int = maxAttempts) -> Bool {
        !connected && attempt < maxAttempts
    }
}
#endif
