import Foundation

/// Shared "has the connect landed yet?" poll for provider OAuth flows (AITD-362).
///
/// Every provider whose callback ends on a plain "return to the app" page — GitHub Issues and
/// Copilot — closes its `ASWebAuthenticationSession` on Done rather than on an app-scheme
/// redirect. Done can be tapped before the callback has filed the token, so the status is
/// polled rather than read once. Pure and testable; the sleeping is the caller's.
enum ConnectionPoll {
    static let maxAttempts = 20      // ~40s at 2s intervals
    static let intervalNanos: UInt64 = 2_000_000_000

    /// Keep polling while not yet connected and under the attempt cap.
    static func shouldContinue(attempt: Int, connected: Bool, maxAttempts: Int = maxAttempts) -> Bool {
        !connected && attempt < maxAttempts
    }
}
