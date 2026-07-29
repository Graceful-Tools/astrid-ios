import XCTest
@testable import Astrid_App

/// Whitelabel (task 97208a72) — the SERVER is the authority on the brand's text.
///
/// Three sources could disagree before this: the iOS Info.plist, the web deployment's
/// env, and `/api/v1/capabilities`, whose `brand` block the client did not even decode.
/// One binary can point at several deployments (the DEBUG server picker does exactly
/// that), so a build-time-only brand is wrong for the same reason a build-time-only
/// capability set was.
///
/// The server supplies TEXT only. The accent stays build-time — see
/// `testAccentIsNotServerDriven` for why that is a decision and not an omission.
final class ServerBrandTests: XCTestCase {

    private func decode(_ json: String) throws -> ServerCapabilities {
        try JSONDecoder().decode(ServerCapabilities.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testDecodesTheBrandBlock() throws {
        let caps = try decode("""
        {"brand":{"appName":"Acme","wordmark":"ACME","slogan":"Ship it.","agentName":"Ada"}}
        """)

        XCTAssertEqual(caps.brand.appName, "Acme")
        XCTAssertEqual(caps.brand.wordmark, "ACME")
        XCTAssertEqual(caps.brand.slogan, "Ship it.")
        XCTAssertEqual(caps.brand.agentName, "Ada")
    }

    /// An older deployment sends no `brand` block at all. That must decode, not throw —
    /// the same reason every other section uses `decodeIfPresent`.
    func testMissingBrandBlockFallsBackToTheBuild() throws {
        let caps = try decode(#"{"auth":{"google":true}}"#)

        XCTAssertNil(caps.brand.appName)
        XCTAssertEqual(caps.brand.resolvedAppName, Brand.appName)
        XCTAssertEqual(caps.brand.resolvedWordmark, Brand.wordmark)
        XCTAssertEqual(caps.brand.resolvedSlogan, Brand.slogan)
        XCTAssertEqual(caps.brand.resolvedAgentName, Brand.agentName)
    }

    /// A partially-populated block takes what it has and falls back for the rest, so a
    /// server can add one field without the client needing a release.
    func testPartialBrandBlockFallsBackPerField() throws {
        let caps = try decode(#"{"brand":{"appName":"Acme"}}"#)

        XCTAssertEqual(caps.brand.resolvedAppName, "Acme")
        // Wordmark is not supplied — derive it from the SERVER's name, not from Astrid's.
        XCTAssertEqual(caps.brand.resolvedWordmark, "acme")
        XCTAssertEqual(caps.brand.resolvedAgentName, "Acme")
    }

    /// The brand block must not break the capability decoding beside it.
    func testBrandBlockCoexistsWithCapabilities() throws {
        let caps = try decode("""
        {"auth":{"google":false},"brand":{"appName":"Acme"},"sync":{"googleTasks":false}}
        """)

        XCTAssertFalse(caps.auth.google)
        XCTAssertFalse(caps.sync.googleTasks)
        XCTAssertEqual(caps.brand.resolvedAppName, "Acme")
    }

    // MARK: - Untrusted input

    /// Defence in depth. A release build only talks to `Brand.productionBaseURL` — the
    /// server picker is `#if DEBUG` with three fixed options — so this is not
    /// attacker-chosen input. It is still network data rendered straight into the UI
    /// chrome, and validating it costs nothing.
    func testBlankServerValuesFallBackRatherThanBlankingTheUI() throws {
        let caps = try decode(#"{"brand":{"appName":"","wordmark":"   ","slogan":"\n"}}"#)

        XCTAssertEqual(caps.brand.resolvedAppName, Brand.appName)
        XCTAssertEqual(caps.brand.resolvedWordmark, Brand.wordmark)
        XCTAssertEqual(caps.brand.resolvedSlogan, Brand.slogan)
    }

    func testServerValuesAreTrimmed() throws {
        let caps = try decode(#"{"brand":{"appName":"  Acme  "}}"#)
        XCTAssertEqual(caps.brand.resolvedAppName, "Acme")
    }

    /// An unbounded name would break the sign-in lockup — and a megabyte of it would be
    /// a cheap way to make the app unusable. Bounded, not merely trimmed.
    func testOverlongServerValuesAreRejected() throws {
        let huge = String(repeating: "A", count: 5_000)
        let caps = try decode(#"{"brand":{"appName":"\#(huge)"}}"#)

        XCTAssertEqual(caps.brand.resolvedAppName, Brand.appName,
                       "an absurd name must fall back, not render")
    }

    func testValuesAtTheLengthLimitAreAccepted() throws {
        let atLimit = String(repeating: "A", count: ServerCapabilities.BrandInfo.maxValueLength)
        let caps = try decode(#"{"brand":{"appName":"\#(atLimit)"}}"#)
        XCTAssertEqual(caps.brand.resolvedAppName, atLimit)
    }

    /// Newlines would let a server inject extra lines into the sign-in lockup.
    func testControlCharactersAreRejected() throws {
        let caps = try decode(#"{"brand":{"appName":"Acme\nSign in with your password"}}"#)
        XCTAssertEqual(caps.brand.resolvedAppName, Brand.appName)
    }

    /// U+202E reverses rendering — the classic way to make a string display as something
    /// other than what it says, which on a sign-in lockup is a spoofing primitive.
    ///
    /// These pass today because Foundation's `.controlCharacters` is Unicode Cc AND Cf,
    /// so it already covers them. That is not obvious from the name, which is exactly why
    /// the behaviour is pinned here: narrowing the check to "reject newlines" looks
    /// equivalent and silently reopens the hole. Mutation-tested — that narrowing fails
    /// this test and `testInvisibleFormattingCharactersAreRejected`.
    func testBidirectionalOverridesAreRejected() throws {
        for scalar in ["\u{202E}", "\u{202D}", "\u{202A}", "\u{202B}", "\u{2066}", "\u{2067}", "\u{2068}"] {
            let caps = try decode(#"{"brand":{"appName":"Acme\#(scalar)evil"}}"#)
            XCTAssertEqual(caps.brand.resolvedAppName, Brand.appName,
                           "U+\(String(scalar.unicodeScalars.first!.value, radix: 16)) should be rejected")
        }
    }

    /// A zero-width joiner or invisible separator can pad a name past what looks
    /// reasonable, or hide characters inside it.
    func testInvisibleFormattingCharactersAreRejected() throws {
        let caps = try decode(#"{"brand":{"appName":"Ac\#u{200B}me"}}"#)
        XCTAssertEqual(caps.brand.resolvedAppName, Brand.appName)
    }

    /// Ordinary non-Latin brand names must still work — the filter targets rendering
    /// attacks, not non-English brands.
    func testNonLatinBrandNamesAreAccepted() throws {
        for name in ["アクメ", "Ακμή", "Акме", "אקמה", "شركة"] {
            let caps = try decode(#"{"brand":{"appName":"\#(name)"}}"#)
            XCTAssertEqual(caps.brand.resolvedAppName, name, "\(name) should be accepted")
        }
    }

    // MARK: - Before the first fetch

    /// The sign-in screen renders before any network call completes. Whatever it reads
    /// must already be the build's brand — never blank, never a placeholder that flashes.
    @MainActor
    func testPermissiveStateAlreadyCarriesTheBuildBrand() {
        let brand = ServerCapabilities.permissive.brand

        XCTAssertEqual(brand.resolvedAppName, Brand.appName)
        XCTAssertEqual(brand.resolvedWordmark, Brand.wordmark)
        XCTAssertEqual(brand.resolvedSlogan, Brand.slogan)
        XCTAssertFalse(brand.resolvedWordmark.isEmpty)
    }

    // MARK: - Deliberate omissions

    /// The server does NOT get to set the host or the agent-email domain. Those are
    /// trust boundaries — a server claiming a different brand domain would be telling the
    /// client which cookies to clear and which Universal Links belong to it.
    func testHostAndAgentDomainAreNotServerDriven() throws {
        let caps = try decode("""
        {"brand":{"appName":"Acme","host":"evil.example","agentEmailDomain":"evil.example"}}
        """)

        XCTAssertEqual(Brand.host, "astrid.cc")
        XCTAssertEqual(Brand.agentEmailDomain, "astrid.cc")
        XCTAssertFalse(Brand.isBrandCookieDomain("evil.example"))
        XCTAssertEqual(caps.brand.resolvedAppName, "Acme", "text still applies")
    }

    /// The accent stays build-time. Theme resolves its colours once at launch (static
    /// let) precisely so a per-render hex parse never happens; making it server-driven
    /// would mean an observable theme and a re-render cost on every colour read. Text
    /// costs nothing to swap; colour does.
    func testAccentIsNotServerDriven() throws {
        // Delimited ##"…"## because the hex colour contains `"#`, which would otherwise
        // close a single-# raw string.
        let caps = try decode(##"{"brand":{"appName":"Acme","accentColor":"#ff0000"}}"##)

        XCTAssertEqual(Brand.accentColorHex, "#3b82f6")
        XCTAssertEqual(caps.brand.resolvedAppName, "Acme")
    }
}
