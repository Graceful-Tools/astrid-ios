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
        "BrandAccentColor", "BrandAccentHoverColor", "BrandAccentTextColor", "BrandCharacterImage",
        "BrandAccentInkColor", "BrandAccentInkDarkColor", "BrandURLScheme",
    ]

    /// The variant's bundle id, as the script recorded it.
    private var variantBundleId: String {
        get throws {
            let data = Data(try RepositoryLocator.source(at: "Brands/Whitelabel/variant.json").utf8)
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try XCTUnwrap(record["bundleId"] as? String)
        }
    }

    /// Astrid's value as the variant must carry it: the drag type and the sync task renamed for
    /// the variant, and the app's own URL type registering the variant's scheme (AITD-616).
    private func reidentified(_ key: String, _ value: Any, bundleId: String, scheme: String) -> Any {
        switch key {
        case "BGTaskSchedulerPermittedIdentifiers":
            return (value as? [String] ?? []).map { $0 == "cc.astrid.app.sync" ? "\(bundleId).sync" : $0 }
        case "UTExportedTypeDeclarations":
            return (value as? [[String: Any]] ?? []).map { type in
                var type = type
                if type["UTTypeIdentifier"] as? String == "cc.astrid.board-card" { type["UTTypeIdentifier"] = "\(bundleId).board-card" }
                return type
            }
        case "CFBundleURLTypes":
            return (value as? [[String: Any]] ?? []).map { urlType in
                var urlType = urlType
                if urlType["CFBundleURLName"] as? String == "cc.astrid.app" { urlType["CFBundleURLSchemes"] = [scheme] }
                return urlType
            }
        default:
            return value
        }
    }

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

    /// A Services entry as the variant carries it (AITD-513): menu title and port renamed,
    /// the NSMessage selector left alone.
    private func renamedService(_ service: [String: Any], to name: String) -> [String: Any] {
        var service = service
        if var item = service["NSMenuItem"] as? [String: String] {
            item = item.mapValues { $0.replacingOccurrences(of: "Astrid", with: name) }
            service["NSMenuItem"] = item
        }
        if service["NSPortName"] as? String == "Astrid" { service["NSPortName"] = name }
        return service
    }

    /// The app's own name — Mac bundle, menu bar, Services port. The brand name is what the
    /// prompts say; a partner can name the app differently ("Acme" vs "Acme Tasks").
    private var variantAppName: String {
        get throws { try XCTUnwrap(try plist("Brands/Whitelabel/Info-iOS.plist")["CFBundleDisplayName"] as? String) }
    }

    private var variantBrandName: String {
        get throws { try XCTUnwrap(try plist("Brands/Whitelabel/Info-iOS.plist")["BrandName"] as? String) }
    }

    private func assertVariant(_ variant: String, matches base: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let astrid = try plist(base)
        let brand = try plist(variant)
        let name = try variantBrandName
        let appName = try variantAppName
        let bundleId = try variantBundleId
        let scheme = Brand.resolveURLScheme(try plist("Brands/Whitelabel/Info-iOS.plist")["BrandURLScheme"] as? String)
        for (key, astridValue) in astrid where !brandedKeys.contains(key) {
            let value = reidentified(key, astridValue, bundleId: bundleId, scheme: scheme)
            guard let copy = brand[key] else {
                XCTFail("\(variant) lacks \(key), which \(base) has — re-run scripts/make-brand-variant.sh", file: file, line: line)
                continue
            }
            var expected = String(describing: value)
            if isUsageDescription(key) { expected = expected.replacingOccurrences(of: "Astrid", with: name) }
            if ["BGTaskSchedulerPermittedIdentifiers", "UTExportedTypeDeclarations", "CFBundleURLTypes"].contains(key) {
                XCTAssertEqual(copy as? NSArray, value as? NSArray,
                               "\(variant) has a stale \(key) — re-run scripts/make-brand-variant.sh", file: file, line: line)
                continue
            }
            if key == "NSServices", let services = value as? [[String: Any]] {
                XCTAssertEqual(copy as? NSArray, services.map { renamedService($0, to: appName) } as NSArray,
                               "\(variant) has a stale \(key) — re-run scripts/make-brand-variant.sh", file: file, line: line)
                continue
            }
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

    /// The build settings of the Whitelabel configuration of the target that builds `product`.
    private func whitelabelSettings(bundleId: String) throws -> String {
        let project = try RepositoryLocator.source(at: "Astrid App.xcodeproj/project.pbxproj")
        let blocks = project.components(separatedBy: "isa = XCBuildConfiguration;").dropFirst()
        let block = try XCTUnwrap(blocks.first {
            $0.contains("PRODUCT_BUNDLE_IDENTIFIER = \"\(bundleId)\";") && $0.contains("name = Whitelabel;")
                && $0.contains("SDKROOT = macosx;")
        }, "no Whitelabel macOS configuration for \(bundleId)")
        return String(block.prefix { $0 != "}" })
    }

    /// AITD-513: the Mac variant kept PRODUCT_NAME = Astrid — Astrid.app, "About Astrid",
    /// "Quit Astrid" — and its Services item said "Add to Astrid".
    func testTheWhitelabelMacAppIsNamedForTheBrand_AITD513() throws {
        let name = try variantAppName
        let settings = try whitelabelSettings(bundleId: "Graceful-Tools-Inc.Whitelabel")
        XCTAssertTrue(settings.contains("PRODUCT_NAME = \(name);") || settings.contains("PRODUCT_NAME = \"\(name)\";"),
                      "Whitelabel Mac must build \(name).app")
        XCTAssertFalse(settings.contains("Astrid "), "a Whitelabel Mac build setting still names Astrid")

        let services = try XCTUnwrap(try plist("Brands/Whitelabel/Info-Mac.plist")["NSServices"] as? [[String: Any]])
        XCTAssertFalse(services.isEmpty)
        for service in services {
            let title = (service["NSMenuItem"] as? [String: String])?["default"] ?? ""
            XCTAssertEqual(title, "Add to \(name)", "the Services menu still reads \(title)")
            // AppKit delivers a service to the port named after the app; Astrid's port would
            // never reach Whitelabel.app.
            XCTAssertEqual(service["NSPortName"] as? String, name)
            // The selector is code, not copy — MacServiceProvider.addToAstrid(_:userData:error:).
            XCTAssertEqual(service["NSMessage"] as? String, "addToAstrid")
        }
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

    /// AITD-616: the variant's drag type and background task are its own, and the scheme it
    /// registers is the one its Brand answers.
    func testTheWhitelabelAppHasItsOwnSystemIdentifiers_AITD616() throws {
        for path in ["Brands/Whitelabel/Info-iOS.plist", "Brands/Whitelabel/Info-Mac.plist"] {
            let source = try RepositoryLocator.source(at: path)
            XCTAssertFalse(source.contains("cc.astrid.board-card"), "\(path) exports Astrid's drag type")
            XCTAssertFalse(source.contains("cc.astrid.app.sync"), "\(path) claims Astrid's BGTask id")
        }
        let ios = try plist("Brands/Whitelabel/Info-iOS.plist")
        let registered = (ios["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .first { $0["CFBundleURLName"] as? String == "cc.astrid.app" }?["CFBundleURLSchemes"] as? [String]
        XCTAssertEqual(registered, [Brand.resolveURLScheme(ios["BrandURLScheme"] as? String)])
    }

    func testAstridKeepsItsOwnAppGroup() {
        // Debug/Release Info.plists carry no AppGroupIdentifier, so Astrid falls back to its own.
        XCTAssertEqual(ShareDataManager.appGroupIdentifier, "group.gracefultools.astrid")
    }
}
