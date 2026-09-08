import XCTest

/// Regression for Astrid task 427a8eec-31a1-442e-9a8d-205f7c7fff73.
///
/// The policy is pure and tested separately; this guards the two shapes in the view
/// that made the policy necessary, since both read as harmless in review.
final class ChatPanelPollingGuardTests: XCTestCase {
    private var source: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            return try String(
                contentsOf: root.appendingPathComponent("Astrid App/Views/Chat/ChatPanelView.swift"),
                encoding: .utf8
            )
        }
    }

    /// The poll must be started through the policy, never straight from channel load.
    func testPollingIsNotStartedUnconditionallyOnChannelLoad() throws {
        XCTAssertFalse(
            try source.contains("startPolling(channelId: resolvedChannelId)"),
            "loadChannel starts the 3 s poll regardless of stream state — route it through ChatPollingPolicy"
        )
        XCTAssertTrue(
            try source.contains("ChatPollingPolicy.shouldPoll"),
            "ChatPanelView should decide whether to poll through ChatPollingPolicy"
        )
    }

    /// The sign-in sheet polled `isSignedInToServer` — a keychain read — once a
    /// second for as long as it was open, rather than observing auth state.
    func testSignInSheetDoesNotPollOncePerSecond() throws {
        XCTAssertFalse(
            try source.contains("Timer.publish(every: 1"),
            "The sign-in sheet should observe AuthManager.$isAuthenticated, not poll at 1 Hz"
        )
    }
}
