import XCTest
@testable import Astrid_App

/// AITD-512: user-facing copy that named Astrid outright, so a partner build said "A new
/// Astrid is ready" and posted an unlocalized "Task Due Soon".
///
/// What the string files must hold — the brand as `%@`, the due-soon title in every language —
/// is checked once by `scripts/check-source-contracts.mjs` (rule localized-keys, AITD-533). What
/// stays here is what only the running app can say: how those strings resolve in the bundle.
final class WhitelabelCopyTests: XCTestCase {

    /// An Astrid build still reads exactly as before, with the brand handed in.
    func testUpdateTitleTakesTheBrandName_AITD512() {
        let format = NSLocalizedString("update.available_title", comment: "")
        XCTAssertTrue(format.contains("%@"), "the title must take the app's name as an argument")
        XCTAssertEqual(String(format: format, Brand.appName), "A new Astrid is ready")
    }

    /// The due-soon reminder title resolves in the bundle rather than falling back to its key.
    func testDueSoonTitleIsLocalized_AITD512() {
        XCTAssertEqual(NSLocalizedString("notifications.due_soon_title", comment: ""), "Task Due Soon")
    }
}
