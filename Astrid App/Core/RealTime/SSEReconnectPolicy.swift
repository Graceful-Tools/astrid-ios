//  SSEReconnectPolicy.swift
//  When the live-update stream should retry, and how long it waits — pure, so the rule is testable
//  without a socket.
//
//  The stream gives up after a bounded number of attempts, which is right for a transient failure
//  but wrong for a Mac that has been ASLEEP: every attempt burns while the machine is offline, and
//  once exhausted nothing ever revived the connection — live updates stayed dead until relaunch.
//  Waking (or regaining the network) therefore RESETS the policy rather than continuing the old
//  countdown.
import Foundation

enum SSEReconnectPolicy {
    static let maxAttempts = 5

    /// Exponential backoff, capped so a long outage does not push the next try minutes away.
    static func delay(attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(max(attempt, 1))), 60.0)
    }

    /// Should we retry after this many failed attempts?
    static func shouldRetry(attempt: Int, max: Int = maxAttempts) -> Bool {
        attempt < max
    }

    /// A 401 means the session is gone — retrying cannot help, so the stream stops instead of
    /// hammering the server.
    static func shouldRetry(afterStatusCode code: Int) -> Bool {
        code != 401
    }

    /// After a wake or a network change the count starts over: the previous failures describe a
    /// world that no longer exists.
    static func attemptsAfterRecovery() -> Int { 0 }
}
