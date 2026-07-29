import XCTest
@testable import Astrid_App

/// Whitelabel (task 97208a72) — the brand-bearing values that a user actually SEES.
///
/// The web app shipped an Astrid wordmark on a partner's sign-in page because the
/// literal was lowercase (`<h1>astrid</h1>`) and every sweep was case-sensitive. iOS and
/// Mac had the identical bug, in `LoginView` and `MacAuthGateView`. These pin the fix.
final class BrandIdentityTests: XCTestCase {

    // MARK: - Wordmark and slogan

    /// The header lockup draws the name in lowercase. That is a TYPOGRAPHIC choice about
    /// Astrid's mark, not a rule about names — a partner called "Acme" may well want
    /// "Acme" — so it is configurable, defaulting to the lowercased brand name.
    func testWordmarkDefaultsToTheLowercasedAppName() {
        XCTAssertEqual(Brand.wordmark, "astrid")
        XCTAssertEqual(Brand.wordmark, Brand.appName.lowercased())
    }

    /// The slogan is a brand value, not a translation. It defaults to the localized
    /// `auth.tagline` so Astrid keeps its 12 translations, and a partner overrides it
    /// with one string rather than commissioning twelve.
    func testSloganDefaultsToTheLocalizedTagline() {
        XCTAssertEqual(Brand.slogan, "Get it done!")
        XCTAssertFalse(Brand.slogan.isEmpty)
    }

    // MARK: - Export filenames

    func testExportFilePrefixFollowsTheWordmark() {
        XCTAssertEqual(Brand.exportFilePrefix, "astrid-export")
    }

    // The Mac save panel's filename is pinned in MacBrandIdentityTests — MacDataExport
    // is macOS-only, and the two platforms must agree on the prefix.

    // MARK: - Assistant persona

    /// The on-device model is told "You are Astrid" and then says so to the user, which
    /// makes it as user-visible as any label. Mirrors NEXT_PUBLIC_BRAND_AGENT_NAME on web.
    func testAgentNameDefaultsToTheAppName() {
        XCTAssertEqual(Brand.agentName, "Astrid")
        XCTAssertEqual(Brand.agentName, Brand.appName)
    }

    /// The system prompt must name the BRAND's assistant, not Astrid's.
    func testOnDeviceInstructionsNameTheBrandAssistant() {
        let instructions = AppleFoundationModelService.personaInstructions(today: "2026-07-28")

        XCTAssertTrue(instructions.contains(Brand.agentName),
                      "persona should introduce itself as the brand assistant: \(instructions)")
        XCTAssertTrue(instructions.contains("2026-07-28"), "caller context should survive")
    }

    // MARK: - Cookie domain matching

    /// Sign-out clears the brand's cookies. The old test was
    /// `$0.domain.contains("astrid")`, which is both brand-coupled AND too broad.
    func testBrandCookieDomainMatchesTheHostAndItsSubdomains() {
        XCTAssertTrue(Brand.isBrandCookieDomain("astrid.cc"))
        XCTAssertTrue(Brand.isBrandCookieDomain("www.astrid.cc"))
        XCTAssertTrue(Brand.isBrandCookieDomain("api.astrid.cc"))
        // Cookie domains are commonly stored with a leading dot.
        XCTAssertTrue(Brand.isBrandCookieDomain(".astrid.cc"))
        XCTAssertTrue(Brand.isBrandCookieDomain("ASTRID.CC"), "host matching is case-insensitive")
    }

    /// The leading dot is load-bearing. A bare `hasSuffix("astrid.cc")` also accepts
    /// `evil-astrid.cc`, and `contains("astrid")` accepts `astrid.evil.com` — either
    /// would have this app deleting, or believing it owns, an attacker's cookies.
    func testBrandCookieDomainRejectsLookalikes() {
        XCTAssertFalse(Brand.isBrandCookieDomain("evil-astrid.cc"))
        XCTAssertFalse(Brand.isBrandCookieDomain("astrid.cc.evil.com"))
        XCTAssertFalse(Brand.isBrandCookieDomain("astrid.evil.com"))
        XCTAssertFalse(Brand.isBrandCookieDomain("notastrid.cc"))
        XCTAssertFalse(Brand.isBrandCookieDomain("example.com"))
        XCTAssertFalse(Brand.isBrandCookieDomain(""))
    }
}
