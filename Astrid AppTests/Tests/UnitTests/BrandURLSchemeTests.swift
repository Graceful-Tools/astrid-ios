import AstridCore
import UniformTypeIdentifiers
import XCTest
@testable import Astrid_App

/// AITD-616 — the app's URL scheme and its two system identifiers are the brand's.
///
/// `"astrid"` was written into eight call sites, so a partner app installed beside Astrid
/// registered and answered the same scheme: a tap on `astrid://tasks/…` could open either app,
/// and a sign-in callback could land in the wrong one. The server already returns the browser to
/// its deployment's `NEXT_PUBLIC_BRAND_APP_URL_SCHEME`, so the app reads the same profile key.
final class BrandURLSchemeTests: XCTestCase {

    // MARK: - Resolution

    func testAstridKeepsItsScheme_AITD616() {
        XCTAssertEqual(Brand.urlScheme, "astrid")
    }

    func testAConfiguredSchemeIsUsedLowercased_AITD616() {
        XCTAssertEqual(Brand.resolveURLScheme("acmetasks"), "acmetasks")
        XCTAssertEqual(Brand.resolveURLScheme("  AcmeTasks "), "acmetasks", "schemes are case-insensitive; compare one form")
        XCTAssertEqual(Brand.resolveURLScheme("acme-tasks.v2+x"), "acme-tasks.v2+x")
        XCTAssertEqual(Brand.resolveURLScheme("acme://"), "acme", "a profile written with :// still names the scheme")
    }

    /// RFC 3986: a letter, then letters, digits, `+`, `-` or `.`. Anything else would register a
    /// scheme the system never delivers, so it falls back rather than breaking sign-in.
    func testAnInvalidSchemeFallsBackToAstrid_AITD616() {
        for raw in [nil, "", "   ", "1acme", "acme tasks", "acme_tasks", "$(BRAND_URL_SCHEME)", "ac/me"] as [String?] {
            XCTAssertEqual(Brand.resolveURLScheme(raw), "astrid", "\(raw ?? "nil")")
        }
    }

    // MARK: - Every place the scheme is used

    func testInAppLinksUseTheBrandScheme_AITD616() throws {
        XCTAssertEqual(Brand.appURL("tasks/abc")?.absoluteString, "\(Brand.urlScheme)://tasks/abc")
        for kind in [MarkdownReference.user, .list, .task] {
            let url = try XCTUnwrap(MarkdownRendering.url(for: kind, id: "x1"))
            XCTAssertEqual(url.scheme, Brand.urlScheme, "\(kind)")
        }
    }

    func testCallbacksAndRoutingUseTheBrandScheme_AITD616() {
        XCTAssertEqual(DesktopHandoff.callbackScheme, Brand.urlScheme)
    }

    // MARK: - System identifiers, read from the app's own declarations

    /// The board's drag type and the background sync task are declared in Info.plist; a partner
    /// variant re-identifies both (`make-brand-variant.sh`), so the code reads them back rather
    /// than naming Astrid's.
    func testTheDeclaredIdentifiersAreFoundBySuffix_AITD616() {
        XCTAssertEqual(Brand.declaredIdentifier(in: ["com.acme.tasks.sync"], suffix: ".sync", fallback: "cc.astrid.app.sync"),
                       "com.acme.tasks.sync")
        XCTAssertEqual(Brand.declaredIdentifier(in: ["other.thing", "com.acme.tasks.board-card"], suffix: ".board-card",
                                                fallback: "cc.astrid.board-card"),
                       "com.acme.tasks.board-card")
        XCTAssertEqual(Brand.declaredIdentifier(in: [], suffix: ".sync", fallback: "cc.astrid.app.sync"), "cc.astrid.app.sync")
    }

    func testAstridsIdentifiersAreUnchanged_AITD616() {
        XCTAssertEqual(Brand.backgroundSyncTaskIdentifier, "cc.astrid.app.sync")
        XCTAssertEqual(Brand.boardCardTypeIdentifier, "cc.astrid.board-card")
        XCTAssertEqual(BackgroundSyncHandler.syncTaskIdentifier, Brand.backgroundSyncTaskIdentifier)
        XCTAssertEqual(UTType.astridBoardCard.identifier, Brand.boardCardTypeIdentifier)
    }

    // MARK: - Profile

    func testTheProfileKeyIsTheOneTheServerReads_AITD616() {
        XCTAssertEqual(BrandProfile.keyMap["NEXT_PUBLIC_BRAND_APP_URL_SCHEME"], "BrandURLScheme")
    }
}
