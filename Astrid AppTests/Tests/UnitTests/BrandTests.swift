import XCTest
@testable import Astrid_App

/// Whitelabel Phase 5 (task 97208a72) — Brand is the single source of truth for
/// brand-bearing values in the iOS and Mac apps, mirroring lib/brand/config.ts on web.
///
/// Brand-bearing copy stores the app name as positional argument 1 (`%1$@`) because
/// `.strings` files have no named placeholders. Getting that numbering wrong is silent
/// — the string renders with a stray argument or drops one — so it is pinned here.
final class BrandTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultsAreTheAstridValues() {
        XCTAssertEqual(Brand.appName, "Astrid")
        XCTAssertEqual(Brand.host, "astrid.cc")
        XCTAssertEqual(Brand.agentEmailDomain, "astrid.cc")
        XCTAssertEqual(Brand.supportEmail, "support@astrid.cc")
        XCTAssertEqual(Brand.inboundTaskEmail, "remindme@astrid.cc")
    }

    func testProductionBaseURLHasSchemeAndNoTrailingSlash() {
        XCTAssertEqual(Brand.productionBaseURL, "https://astrid.cc")
        XCTAssertFalse(Brand.productionBaseURL.hasSuffix("/"))
    }

    /// DeepLinkManager and MacDeepLink both route Universal Links through this set.
    func testWebHostsCoverApexAndWww() {
        XCTAssertTrue(Brand.webHosts.contains("astrid.cc"))
        XCTAssertTrue(Brand.webHosts.contains("www.astrid.cc"))
        XCTAssertFalse(Brand.webHosts.contains("evil.example"))
        // A lookalike host must not be accepted — this is a link-routing boundary.
        XCTAssertFalse(Brand.webHosts.contains("astrid.cc.evil.example"))
    }

    func testLogSubsystemFollowsTheBundle() {
        XCTAssertFalse(Brand.logSubsystem.isEmpty)
    }

    // MARK: - Localized copy

    func testLocalizedSubstitutesTheAppNameWithNoExtraArguments() {
        XCTAssertEqual(Brand.localized("welcome.title"), "Welcome to Astrid!")
    }

    /// `debug.app_version` is "%1$@ v%2$@" — brand first, caller argument second.
    func testLocalizedPlacesCallerArgumentsAfterTheBrand() {
        XCTAssertEqual(Brand.localized("debug.app_version", "1.2.3"), "Astrid v1.2.3")
    }

    /// The trickiest conversion: this string already had a `%@`, which had to shift to
    /// `%2$@` when the brand claimed slot 1.
    func testLocalizedHandlesAStringThatAlreadyHadAnArgument() {
        let result = Brand.localized("reminders.import_into_footer", "Groceries")

        XCTAssertTrue(result.contains("Astrid"), "app name should be substituted: \(result)")
        XCTAssertTrue(result.contains("Groceries"), "caller argument should survive: \(result)")
        XCTAssertFalse(result.contains("%"), "no format specifier should remain: \(result)")
    }

    /// Every brand-bearing key must be fully substituted — a leftover `%1$@` means a
    /// call site was missed, and a leftover `%2$@` means an argument was.
    func testBrandBearingKeysRenderWithoutLeftoverSpecifiers() {
        let noArgumentKeys = [
            "welcome.title",
            "empty_state.my_tasks",
            "settings.ai.about_description",
            "settings.ai.encryption_info",
            "reminders.access_footer",
            "reminders.import_footer",
            "reminders.astrid_list",
            "members.astrid_users",
            "sync.github_footer",
            "sync.google_footer",
            "mac.open_astrid",
            "mac.welcome",
        ]

        for key in noArgumentKeys {
            let rendered = Brand.localized(key)
            XCTAssertFalse(rendered.contains("%"), "\(key) still has a format specifier: \(rendered)")
            XCTAssertNotEqual(rendered, key, "\(key) is missing from Localizable.strings")
        }
    }
}
