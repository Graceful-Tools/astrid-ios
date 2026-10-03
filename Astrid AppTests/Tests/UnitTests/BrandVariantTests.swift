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

    private func assertVariant(_ variant: String, matches base: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let astrid = try plist(base)
        let brand = try plist(variant)
        for (key, value) in astrid where !brandedKeys.contains(key) {
            guard let copy = brand[key] else {
                XCTFail("\(variant) lacks \(key), which \(base) has — re-run scripts/make-brand-variant.sh", file: file, line: line)
                continue
            }
            XCTAssertEqual(String(describing: copy), String(describing: value),
                           "\(variant) has a stale \(key) — re-run scripts/make-brand-variant.sh", file: file, line: line)
        }
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
