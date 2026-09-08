import XCTest
@testable import Astrid_App

/// Regression for Astrid task 427a8eec-31a1-442e-9a8d-205f7c7fff73.
///
/// `ChatPanelView.loadChannel` subscribed to SSE and then started a 3 s repeating
/// timer unconditionally. Every tick was a full `refreshMessagesFromServer` — 20
/// message fetches a minute, for as long as a list's chat was on screen, while the
/// stream that made them redundant was connected and delivering the same events.
final class ChatPollingPolicyTests: XCTestCase {
    func testDoesNotPollWhileTheStreamIsLive() {
        XCTAssertFalse(
            ChatPollingPolicy.shouldPoll(isStreamLive: true, hasChannel: true, isAuthenticated: true),
            "A live stream already delivers created/updated/deleted; polling on top of it is 20 redundant fetches a minute"
        )
    }

    func testPollsWhenTheStreamIsDown() {
        XCTAssertTrue(
            ChatPollingPolicy.shouldPoll(isStreamLive: false, hasChannel: true, isAuthenticated: true),
            "The fallback exists for exactly this case"
        )
    }

    /// Both of these were already guarded inside the timer body, which meant the
    /// timer still woke up 20 times a minute to decide to do nothing.
    func testNeverPollsWithoutAResolvedChannel() {
        XCTAssertFalse(ChatPollingPolicy.shouldPoll(isStreamLive: false, hasChannel: false, isAuthenticated: true))
        XCTAssertFalse(ChatPollingPolicy.shouldPoll(isStreamLive: true, hasChannel: false, isAuthenticated: true))
    }

    func testNeverPollsWhileSignedOut() {
        XCTAssertFalse(ChatPollingPolicy.shouldPoll(isStreamLive: false, hasChannel: true, isAuthenticated: false))
    }

    /// The interval is the fallback's cost when it does run, so it is worth pinning
    /// rather than leaving as a literal in the view.
    func testFallbackIntervalIsUnchanged() {
        XCTAssertEqual(ChatPollingPolicy.interval, 3.0)
    }

    /// `SSEClient.isConnected` is set optimistically inside `connect()`, before the
    /// stream is known to work. Exposing that flag would silence the fallback at the
    /// exact moment the connection is failing, so the observable state starts false
    /// and only the confirmed-streaming transition may set it true.
    @MainActor
    func testStreamStateStartsDownSoTheFallbackRunsUntilTheStreamIsProven() {
        let state = SSEConnectionState()
        XCTAssertFalse(state.isStreamLive)

        state.streamDidBecomeLive()
        XCTAssertTrue(state.isStreamLive)

        state.streamDidStop()
        XCTAssertFalse(state.isStreamLive)
    }
}
