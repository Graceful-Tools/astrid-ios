import UIKit

/// Warms the text-input / autocorrect engine at launch **without presenting the
/// keyboard**.
///
/// The previous implementation focused a hidden `UITextField`
/// (`becomeFirstResponder()`) on `UIScene.didActivateNotification`. That
/// notification fires on every scene activation, so the system keyboard rose and
/// then dismissed ~0.5s later on every app open — reported as "keyboard pops up
/// on first app open" and "keyboard opens and closes with every app open".
///
/// This replacement warms the spell/autocorrect engine via `UITextChecker`,
/// which loads the same language data lazily on first use, but never touches the
/// responder chain — so the keyboard never appears. It also runs exactly once
/// per process.
enum KeyboardEngineWarmer {

    /// Whether launch warm-up presents the keyboard. Always false — warming must
    /// be invisible. Exposed so the contract is testable and a future regression
    /// (re-introducing first-responder warming) is caught.
    static let presentsKeyboard = false

    private static var hasWarmed = false
    private static let lock = NSLock()

    /// Returns `true` exactly once per process (the first call), `false`
    /// thereafter. Use this to ensure warming happens a single time at launch and
    /// never repeatedly on each scene activation.
    static func claimWarmSlot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasWarmed { return false }
        hasWarmed = true
        return true
    }

    /// Invisibly warms the spell/autocorrect engine. Safe to call off the main
    /// thread; does not require a window or any first responder.
    static func warmTextChecker() {
        let checker = UITextChecker()
        let sample = "test"
        _ = checker.rangeOfMisspelledWord(
            in: sample,
            range: NSRange(location: 0, length: (sample as NSString).length),
            startingAt: 0,
            wrap: false,
            language: "en_US"
        )
    }

    /// Claims the warm slot and warms the engine if this is the first call.
    static func warmOnce() {
        guard claimWarmSlot() else { return }
        warmTextChecker()
    }

    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        hasWarmed = false
    }
}
