import SwiftUI
import XCTest
@testable import Astrid_App

/// Whitelabel (task 97208a72) — assertions that only make sense on a PARTNER build.
///
/// Every other brand test pins the Astrid defaults. Those prove the fallbacks, but they
/// cannot prove that Info.plist configuration actually reaches `Brand` at runtime, and
/// they cannot catch an Astrid value leaking into a rebranded build — which is the whole
/// failure mode whitelabeling has, and the one nobody is looking at.
///
/// So this class SKIPS on an Astrid build and runs under an applied brand profile:
///
///     ./scripts/check-brands.sh            # applies each profile, runs this, reverts
///
/// The web's `tests/brands/brand-matrix.test.ts` is the same idea. It can set env per
/// test; Info.plist is fixed for the life of the process, so on iOS the matrix has to be
/// driven from outside by the script.
final class BrandAuditTests: XCTestCase {

    /// Skip unless a non-Astrid brand profile is applied.
    private func requirePartnerBuild() throws {
        guard Brand.appName != "Astrid" else {
            throw XCTSkip("Astrid build — run ./scripts/check-brands.sh to audit a partner brand")
        }
    }

    /// Info.plist configuration must actually reach Brand. If `infoString` silently
    /// returned nil — a mistyped key, a plist not in the built product — every test in
    /// every other brand class would still pass, and the app would ship unbranded.
    func testTheConfiguredBrandActuallyReachesBrand() throws {
        try requirePartnerBuild()

        XCTAssertNotEqual(Brand.appName, "Astrid")

        // Against the profile, not against "not astrid.cc": the whitelabel profile keeps
        // astrid.cc on purpose (AITD-453), and comparing with what the plist actually says
        // is the stronger check anyway — a mistyped key in Brand.swift reads nil and falls
        // back to the default, which no longer equals the configured value.
        for (key, value) in brandValuesByPlistKey {
            guard let expected = configured(key) else { continue }
            XCTAssertEqual(value, expected, "Brand does not reflect Info.plist \(key)")
        }
    }

    /// Nothing Astrid may survive into a partner's build.
    func testNoAstridValueSurvives() throws {
        try requirePartnerBuild()

        let surface: [(String, String)] = [
            ("appName", Brand.appName),
            ("host", Brand.host),
            ("agentEmailDomain", Brand.agentEmailDomain),
            ("supportEmail", Brand.supportEmail),
            ("inboundTaskEmail", Brand.inboundTaskEmail),
            ("wordmark", Brand.wordmark),
            ("slogan", Brand.slogan),
            ("agentName", Brand.agentName),
            ("exportFilePrefix", Brand.exportFilePrefix),
            ("productionBaseURL", Brand.productionBaseURL),
        ]

        // A partner may keep astrid.cc as its DOMAIN — the whitelabel profile does, to
        // share the .astrid.cc sign-in cookie (AITD-453) — so a domain-bearing value is
        // allowed to say astrid when it is exactly what the profile configured. What it
        // may never be is Astrid's DEFAULT surviving an unconfigured key. The name stays
        // strict whatever the domain: no profile configures "Astrid" as its name.
        let configuredDomainValues: [String: String?] = [
            "host": configured("BrandHost"),
            "agentEmailDomain": configured("BrandAgentEmailDomain"),
            "supportEmail": configured("BrandSupportEmail"),
            "inboundTaskEmail": configured("BrandInboundTaskEmail"),
            "productionBaseURL": configured("BrandHost").map { "https://\($0)" },
        ]

        for (name, value) in surface {
            if let expected = configuredDomainValues[name] ?? nil, value == expected {
                XCTAssertFalse(value.contains("Astrid"),
                               "Brand.\(name) names Astrid: \(value)")
                continue
            }
            XCTAssertFalse(value.lowercased().contains("astrid"),
                           "Brand.\(name) still carries an Astrid value: \(value)")
        }
    }

    /// Brand-bearing localized copy must render the CONFIGURED name. This is where a
    /// missed `%1$@` conversion shows up — the string would still say "Astrid".
    func testLocalizedCopyNamesTheConfiguredBrand() throws {
        try requirePartnerBuild()

        let keys = [
            "welcome.title",
            "empty_state.my_tasks",
            "settings.ai.about_description",
            "reminders.astrid_list",
            "members.astrid_users",
            "mac.welcome",
        ]

        for key in keys {
            let rendered = Brand.localized(key)
            XCTAssertFalse(rendered.lowercased().contains("astrid"),
                           "\(key) still names Astrid on a partner build: \(rendered)")
            XCTAssertTrue(rendered.contains(Brand.appName),
                          "\(key) does not name the configured brand: \(rendered)")
            XCTAssertFalse(rendered.contains("%"), "\(key) has a leftover specifier: \(rendered)")
        }
    }

    /// The accent must be the partner's, and every theme variant must have followed it.
    /// This is the assertion the default-build test cannot make: with Astrid configured,
    /// a reverted literal still compares equal to the configured value.
    func testEveryThemeVariantFollowedThePartnerAccent() throws {
        try requirePartnerBuild()
        guard Brand.accentColorHex.lowercased() != Brand.defaultAccentHex else {
            throw XCTSkip("This profile keeps the default accent")
        }

        let astridBlue = Color(hex: Brand.defaultAccentHex)

        XCTAssertEqual(Theme.accent, Brand.accentColor)
        XCTAssertEqual(Theme.Dark.accent, Brand.accentColor)
        XCTAssertEqual(Theme.Ocean.accent, Brand.accentColor)
        XCTAssertEqual(Theme.borderFocus, Brand.accentColor)
        XCTAssertEqual(Theme.Dark.borderFocus, Brand.accentColor)
        XCTAssertEqual(Theme.Ocean.borderFocus, Brand.accentColor)
        XCTAssertEqual(Theme.Dark.bgSelectedBorder, Brand.accentColor)
        XCTAssertEqual(Theme.priorityLow, Brand.accentColor)

        XCTAssertNotEqual(Theme.accent, astridBlue, "the accent is still Astrid blue")
        XCTAssertNotEqual(Theme.Ocean.accent, astridBlue, "Ocean kept Astrid blue")
    }

    /// Semantic colours must NOT follow the brand — a red error stays red.
    func testStatusColoursDidNotFollowTheBrand() throws {
        try requirePartnerBuild()

        XCTAssertNotEqual(Theme.error, Brand.accentColor)
        XCTAssertNotEqual(Theme.warning, Brand.accentColor)
        XCTAssertNotEqual(Theme.success, Brand.accentColor)
        XCTAssertNotEqual(Theme.priorityHigh, Brand.accentColor)
    }

    /// The cookie boundary must move with the brand: a partner build must not treat
    /// astrid.cc cookies as its own, and must claim its own host.
    func testTheCookieBoundaryMovedToThePartnerHost() throws {
        try requirePartnerBuild()

        XCTAssertTrue(Brand.isBrandCookieDomain(Brand.host))
        XCTAssertTrue(Brand.isBrandCookieDomain(".\(Brand.host)"))
        XCTAssertFalse(Brand.isBrandCookieDomain("evil-\(Brand.host)"))

        // Only a partner on its own domain must disown astrid.cc. One that keeps astrid.cc
        // (whitelabel, AITD-453) depends on exactly that cookie for Google sign-in.
        let host = Brand.host.lowercased()
        if host != "astrid.cc" && !host.hasSuffix(".astrid.cc") {
            XCTAssertFalse(Brand.isBrandCookieDomain("astrid.cc"))
        }
    }

    /// The on-device assistant must introduce itself as the partner's.
    func testTheAssistantIntroducesItselfAsThePartnerBrand() throws {
        try requirePartnerBuild()

        let instructions = AppleFoundationModelService.personaInstructions(today: "2026-07-28")
        XCTAssertTrue(instructions.contains(Brand.agentName))
        XCTAssertFalse(instructions.lowercased().contains("you are astrid"))
    }

    // MARK: - What the applied profile configured

    /// The value the applied profile wrote into Info.plist for `key`, or nil when the
    /// profile leaves it to the Brand.swift default. Read with the literal key apply-brand.sh
    /// writes — deliberately not through Brand, which is the thing under test.
    private func configured(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    private var brandValuesByPlistKey: [(String, String)] {
        [
            ("BrandName", Brand.appName),
            ("BrandHost", Brand.host),
            ("BrandAgentEmailDomain", Brand.agentEmailDomain),
            ("BrandSupportEmail", Brand.supportEmail),
            ("BrandInboundTaskEmail", Brand.inboundTaskEmail),
            ("BrandWordmark", Brand.wordmark),
            ("BrandSlogan", Brand.slogan),
            ("BrandAgentName", Brand.agentName),
        ]
    }
}
