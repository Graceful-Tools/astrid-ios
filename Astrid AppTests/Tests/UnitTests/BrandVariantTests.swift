import XCTest
@testable import Astrid_App

/// The Whitelabel app is built from COPIES of Astrid's Info.plists and entitlements
/// (Brands/Whitelabel/, written by scripts/make-brand-variant.sh). A copy drifts silently: add a
/// usage description or a background mode to Info.plist and the Whitelabel app ships without it,
/// and is rejected — or crashes on the first camera tap — long after the change looked done.
///
/// So every key Astrid's file has must be in the variant too, with the same value, except the
/// keys the variant exists to change. Failing here means: run
/// `./scripts/make-brand-variant.sh whitelabel-partner` and commit the result.
final class BrandVariantTests: XCTestCase {

    /// What a brand variant is FOR — the only keys allowed to differ from Astrid's file.
    private let brandedKeys: Set<String> = [
        "CFBundleDisplayName", "AppGroupIdentifier",
        "BrandName", "BrandHost", "BrandAgentEmailDomain", "BrandSupportEmail", "BrandInboundTaskEmail",
        "BrandWordmark", "BrandSlogan", "BrandAgentName",
        "BrandAccentColor", "BrandAccentHoverColor", "BrandAccentTextColor",
    ]

    private func plist(_ path: String) throws -> [String: Any] {
        let data = Data(try RepositoryLocator.source(at: path).utf8)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], path)
    }

    /// Permission prompts are copied with Astrid's name swapped for the brand's (AITD-512), so
    /// they are compared after the same swap: a prompt reworded in Astrid's plist still reads
    /// as stale here.
    private func isUsageDescription(_ key: String) -> Bool {
        key.hasPrefix("NS") && key.hasSuffix("UsageDescription")
    }

    private var variantBrandName: String {
        get throws { try XCTUnwrap(try plist("Brands/Whitelabel/Info-iOS.plist")["BrandName"] as? String) }
    }

    private func assertVariant(_ variant: String, matches base: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let astrid = try plist(base)
        let brand = try plist(variant)
        let name = try variantBrandName
        for (key, value) in astrid where !brandedKeys.contains(key) {
            guard let copy = brand[key] else {
                XCTFail("\(variant) lacks \(key), which \(base) has — re-run scripts/make-brand-variant.sh", file: file, line: line)
                continue
            }
            var expected = String(describing: value)
            if isUsageDescription(key) { expected = expected.replacingOccurrences(of: "Astrid", with: name) }
            XCTAssertEqual(String(describing: copy), expected,
                           "\(variant) has a stale \(key) — re-run scripts/make-brand-variant.sh", file: file, line: line)
        }
    }

    /// AITD-512: the camera, contacts, photos and reminders prompts are the first thing a
    /// partner's user reads, and they said "Astrid". Every NS*UsageDescription in a generated
    /// plist must name the brand instead.
    func testWhitelabelPermissionPromptsNameTheBrand_AITD512() throws {
        let name = try variantBrandName
        for path in ["Brands/Whitelabel/Info-iOS.plist", "Brands/Whitelabel/Info-Mac.plist", "Brands/Whitelabel/Info-Share.plist"] {
            let variant = try plist(path)
            for (key, value) in variant where isUsageDescription(key) {
                let prompt = try XCTUnwrap(value as? String, "\(path) \(key)")
                XCTAssertFalse(prompt.contains("Astrid"), "\(path) \(key) still names Astrid: \(prompt)")
                XCTAssertTrue(prompt.contains(name), "\(path) \(key) does not name \(name): \(prompt)")
            }
        }
        XCTAssertFalse((try plist("Brands/Whitelabel/Info-Share.plist")["CFBundleDisplayName"] as? String ?? "").contains("Astrid"),
                       "the Share extension's name in the share sheet still says Astrid")
    }

    /// Astrid's own prompts are untouched — the rebrand happens only in the variant's copies.
    func testAstridsOwnPermissionPromptsStillSayAstrid_AITD512() throws {
        let camera = try XCTUnwrap(try plist("Info.plist")["NSCameraUsageDescription"] as? String)
        XCTAssertTrue(camera.hasPrefix("Astrid "))
    }

    func testTheWhitelabelPlistsTrackAstrids() throws {
        try assertVariant("Brands/Whitelabel/Info-iOS.plist", matches: "Info.plist")
        try assertVariant("Brands/Whitelabel/Info-Mac.plist", matches: "Astrid Mac/Info.plist")
        try assertVariant("Brands/Whitelabel/Info-Share.plist", matches: "Astrid/Info.plist")
    }

    func testTheWhitelabelAppIsItsOwnApp() throws {
        // Its own group and name — sharing Astrid's App Group would let the two apps read each
        // other's pending shares.
        XCTAssertEqual(try plist("Brands/Whitelabel/Info-iOS.plist")["AppGroupIdentifier"] as? String, "group.gracefultools.whitelabel")
        XCTAssertEqual(try plist("Brands/Whitelabel/Info-Share.plist")["AppGroupIdentifier"] as? String, "group.gracefultools.whitelabel")
        XCTAssertEqual(try plist("Brands/Whitelabel/Info-iOS.plist")["CFBundleDisplayName"] as? String, "Whitelabel")

        for name in ["Whitelabel-iOS", "Whitelabel-Mac", "Whitelabel-Share"] {
            let entitlements = try RepositoryLocator.source(at: "Brands/Whitelabel/\(name).entitlements")
            XCTAssertFalse(entitlements.contains("astrid.cc"), "\(name) must not claim Astrid's domains")
            XCTAssertFalse(entitlements.contains("group.gracefultools.astrid"), "\(name) must not share Astrid's App Group")
        }
    }

    func testAstridKeepsItsOwnAppGroup() {
        // Debug/Release Info.plists carry no AppGroupIdentifier, so Astrid falls back to its own.
        XCTAssertEqual(ShareDataManager.appGroupIdentifier, "group.gracefultools.astrid")
    }
}
