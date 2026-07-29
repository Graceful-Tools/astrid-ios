import XCTest
@testable import Astrid_App

/// Whitelabel (task 97208a72) — ONE brand profile drives web, iOS and Mac.
///
/// `brands/<partner>.brand.json` in the web repo is already the single description of a
/// brand. These tests make the native apps read the same file rather than keeping a
/// parallel description that can drift: a partner should describe their brand once.
///
/// The sharp test here is `testEveryBrandKeyIsMapped`. It parses Brand.swift for the
/// Info.plist keys it actually reads and fails if any of them has no profile mapping —
/// so adding a brand value without a way to configure it is a build failure, not a
/// discovery a partner makes after shipping.
final class BrandProfileTests: XCTestCase {

    // MARK: - Mapping

    func testMapsWebEnvKeysToInfoPlistKeys() {
        let env = [
            "NEXT_PUBLIC_BRAND_NAME": "Acme",
            "NEXT_PUBLIC_BRAND_DOMAIN": "tasks.acme.example",
            "NEXT_PUBLIC_BRAND_WORDMARK": "ACME",
            "NEXT_PUBLIC_BRAND_SLOGAN": "Ship it.",
        ]

        XCTAssertEqual(BrandProfile.infoPlistValues(fromProfileEnv: env), [
            "BrandName": "Acme",
            "BrandHost": "tasks.acme.example",
            "BrandWordmark": "ACME",
            "BrandSlogan": "Ship it.",
        ])
    }

    /// A profile carries web-only settings too (capability switches, image paths). Those
    /// are not iOS's business and must be skipped, not rejected.
    func testIgnoresKeysTheNativeAppsDoNotConsume() {
        let env = [
            "NEXT_PUBLIC_BRAND_NAME": "Acme",
            "NEXT_PUBLIC_BRAND_ENABLE_MCP": "false",
            "NEXT_PUBLIC_BRAND_LOGO": "/images/acme-logo.png",
            "NEXTAUTH_URL": "https://tasks.acme.example",
        ]

        XCTAssertEqual(BrandProfile.infoPlistValues(fromProfileEnv: env), ["BrandName": "Acme"])
    }

    /// The brand domain feeds `BrandHost`, but the AGENT email domain is its own web
    /// variable and its own Info.plist key — the server allows them to diverge.
    func testHostAndAgentDomainMapSeparately() {
        let env = [
            "NEXT_PUBLIC_BRAND_DOMAIN": "tasks.acme.example",
            "BRAND_AGENT_EMAIL_DOMAIN": "agents.acme.example",
        ]

        let values = BrandProfile.infoPlistValues(fromProfileEnv: env)
        XCTAssertEqual(values["BrandHost"], "tasks.acme.example")
        XCTAssertEqual(values["BrandAgentEmailDomain"], "agents.acme.example")
    }

    // MARK: - Drift guard

    /// Every Info.plist key Brand.swift reads must be reachable from a brand profile.
    ///
    /// Parsed from source rather than listed by hand, because a hand-written list is
    /// exactly the thing that goes stale. A new `infoString("BrandFoo")` with no mapping
    /// is a value a partner cannot configure — invisible on an Astrid build, and only
    /// discovered on theirs.
    func testEveryBrandKeyIsMapped() throws {
        let source = try String(contentsOf: brandSourceURL(), encoding: .utf8)

        var keys: Set<String> = []
        var search = source[...]
        while let start = search.range(of: "infoString(\"") {
            let rest = search[start.upperBound...]
            guard let end = rest.range(of: "\"") else { break }
            keys.insert(String(rest[..<end.lowerBound]))
            search = rest[end.upperBound...]
        }

        XCTAssertFalse(keys.isEmpty, "found no Info.plist keys in Brand.swift — parser is broken")

        let mapped = Set(BrandProfile.keyMap.values)
        let unmapped = keys.subtracting(mapped)
        XCTAssertTrue(unmapped.isEmpty,
                      "Brand reads \(unmapped.sorted()) but no brand profile can set them — "
                      + "add a mapping to BrandProfile.keyMap")
    }

    /// And the reverse: a mapping pointing at a key nothing reads is dead configuration
    /// that will silently do nothing when a partner sets it.
    func testEveryMappingPointsAtAKeyBrandReads() throws {
        let source = try String(contentsOf: brandSourceURL(), encoding: .utf8)

        for (env, plistKey) in BrandProfile.keyMap {
            XCTAssertTrue(source.contains("infoString(\"\(plistKey)\")"),
                          "\(env) maps to \(plistKey), which Brand.swift never reads")
        }
    }

    // MARK: - The shared profile

    /// The real payoff: the Acme profile the web deploys from also configures iOS.
    func testTheSharedAcmeProfileConfiguresTheNativeApps() throws {
        let profile = try loadProfile(named: "acme")
        let env = try XCTUnwrap(profile["env"] as? [String: String])
        let values = BrandProfile.infoPlistValues(fromProfileEnv: env)

        XCTAssertEqual(values["BrandName"], "Acme")
        XCTAssertFalse(values.isEmpty)

        // Nothing Astrid may leak through into a partner's build.
        for (key, value) in values {
            XCTAssertFalse(value.lowercased().contains("astrid"),
                           "\(key) still carries an Astrid value: \(value)")
        }
    }

    /// The Astrid profile deliberately sets no environment — it is the regression guard
    /// proving an unconfigured deployment behaves exactly as it does today.
    func testTheAstridProfileConfiguresNothing() throws {
        let profile = try loadProfile(named: "astrid")
        let env = (profile["env"] as? [String: String]) ?? [:]

        XCTAssertTrue(BrandProfile.infoPlistValues(fromProfileEnv: env).isEmpty,
                      "the Astrid profile must stay empty — it proves the defaults are the defaults")
    }

    // MARK: - Helpers

    private func brandSourceURL() throws -> URL {
        try repositoryRoot().appendingPathComponent("Astrid App/Utilities/Brand.swift")
    }

    private func loadProfile(named name: String) throws -> [String: Any] {
        let url = try siblingWebRepository()
            .appendingPathComponent("brands/\(name).brand.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("No \(name).brand.json in the paired web checkout")
        }
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Walk up from this source file to the repository root, identified by the Xcode
    /// project rather than by the folder being named `astrid-ios` — a git worktree is not.
    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Astrid App.xcodeproj").path) {
                return url
            }
        }
        throw XCTSkip("Repository root not found from \(#filePath)")
    }

    /// Prefer the web worktree paired with this one, so a run from a feature worktree
    /// checks the web branch it belongs with rather than whatever is on main.
    private func siblingWebRepository() throws -> URL {
        let root = try repositoryRoot()
        let parent = root.deletingLastPathComponent()
        let suffix = root.lastPathComponent.hasPrefix("astrid-ios")
            ? String(root.lastPathComponent.dropFirst("astrid-ios".count))
            : ""

        for candidate in ["astrid-web\(suffix)", "astrid-web"] {
            let url = parent.appendingPathComponent(candidate)
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("package.json").path) {
                return url
            }
        }
        throw XCTSkip("No astrid-web checkout beside \(root.lastPathComponent)")
    }
}
