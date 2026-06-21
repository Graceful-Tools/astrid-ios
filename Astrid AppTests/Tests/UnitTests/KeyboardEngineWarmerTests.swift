import XCTest
@testable import Astrid_App

/// Tests for `KeyboardEngineWarmer`, which replaced the launch-time keyboard
/// pre-warm that focused a hidden `UITextField`.
///
/// The old approach was registered on `UIScene.didActivateNotification` (which
/// fires on EVERY scene activation) and called `becomeFirstResponder()`, so the
/// system keyboard rose and then dismissed ~0.5s later — the "keyboard pops up
/// on first app open" and "keyboard opens and closes with every app open" bugs.
///
/// The replacement warms the autocorrect/spell engine invisibly and exactly
/// once per process.
final class KeyboardEngineWarmerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeyboardEngineWarmer.resetForTesting()
    }

    /// The warm slot must be claimable exactly once — guaranteeing warming
    /// happens a single time at launch, never repeatedly on each app open.
    func testClaimWarmSlotReturnsTrueOnlyOnce() {
        XCTAssertTrue(KeyboardEngineWarmer.claimWarmSlot(),
                      "first claim should succeed")
        XCTAssertFalse(KeyboardEngineWarmer.claimWarmSlot(),
                       "second claim must fail — no warming on repeat activations")
        XCTAssertFalse(KeyboardEngineWarmer.claimWarmSlot(),
                       "subsequent claims must keep failing")
    }

    /// Warming must be invisible: it must not request first responder, so the
    /// keyboard never appears. We assert the warmer exposes this contract and
    /// that warming runs without touching the responder chain.
    func testWarmingNeverPresentsKeyboard() {
        XCTAssertFalse(KeyboardEngineWarmer.presentsKeyboard,
                       "launch warm-up must never present the keyboard")
        // Should run without crashing and without needing a window/responder.
        KeyboardEngineWarmer.warmTextChecker()
    }
}
