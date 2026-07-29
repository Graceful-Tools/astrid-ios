//  MacBrandAuditTests.swift
//  Whitelabel (task 97208a72) — the partner-build audit, for the Mac target.
//
//  apply-brand.sh writes "Astrid Mac/Info.plist" too, but until this existed nothing
//  ever CHECKED it: check-brands.sh only ran the iOS scheme. That mattered because the
//  Mac target has its own `#if os(macOS)` branch of Theme with its own borderFocus, and
//  its own sign-in gate — a Mac-only whitelabel regression was invisible to every gate.
//
//  Skips on an Astrid build, exactly like the iOS audit.

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacBrandAuditTests: XCTestCase {

    private func requirePartnerBuild() throws {
        guard Brand.appName != "Astrid" else {
            throw XCTSkip("Astrid build — run ./scripts/check-brands.sh to audit a partner brand")
        }
    }

    /// The Mac Info.plist must actually be reaching Brand. It is a different file from
    /// the iOS one, so "iOS is branded" says nothing about this.
    func testTheConfiguredBrandReachesTheMacBuild() throws {
        try requirePartnerBuild()

        XCTAssertNotEqual(Brand.appName, "Astrid")
        XCTAssertNotEqual(Brand.host, "astrid.cc")
        XCTAssertFalse(Brand.wordmark.lowercased().contains("astrid"))
        XCTAssertFalse(Brand.productionBaseURL.contains("astrid.cc"))
    }

    /// macOS resolves the base theme tokens through `themed(...)` per mode, so the accent
    /// has to hold across every one of them — a partner accent that only applied in Ocean
    /// would look like a rendering bug, not a configuration one.
    func testThePartnerAccentHoldsAcrossEveryMacThemeMode() throws {
        try requirePartnerBuild()
        guard Brand.accentColorHex.lowercased() != Brand.defaultAccentHex else {
            throw XCTSkip("This profile keeps the default accent")
        }

        let astridBlue = Color(hex: Brand.defaultAccentHex)
        let key = "themeMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        for mode in ["light", "dark", "ocean"] {
            UserDefaults.standard.set(mode, forKey: key)
            XCTAssertEqual(Theme.accent, Brand.accentColor, "accent wrong in \(mode)")
            XCTAssertEqual(Theme.borderFocus, Brand.accentColor, "focus border wrong in \(mode)")
            XCTAssertNotEqual(Theme.accent, astridBlue, "still Astrid blue in \(mode)")
        }
    }

    /// The Mac export panel must use the partner's filename stem.
    func testMacExportFilenameIsRebranded() throws {
        try requirePartnerBuild()

        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 18
        let gregorian = Calendar(identifier: .gregorian)
        let name = MacDataExport.fileName(format: "json",
                                          date: gregorian.date(from: components)!,
                                          calendar: gregorian)

        XCTAssertTrue(name.hasPrefix(Brand.exportFilePrefix))
        XCTAssertFalse(name.lowercased().contains("astrid"))
    }

    /// Mac-facing localized copy must name the configured brand.
    func testMacLocalizedCopyNamesTheConfiguredBrand() throws {
        try requirePartnerBuild()

        for key in ["mac.open_astrid", "mac.welcome"] {
            let rendered = Brand.localized(key)
            XCTAssertFalse(rendered.lowercased().contains("astrid"),
                           "\(key) still names Astrid: \(rendered)")
            XCTAssertTrue(rendered.contains(Brand.appName), "\(key): \(rendered)")
        }
    }

    /// Semantic colours stay semantic on Mac too.
    func testMacStatusColoursDidNotFollowTheBrand() throws {
        try requirePartnerBuild()

        XCTAssertNotEqual(Theme.error, Brand.accentColor)
        XCTAssertNotEqual(Theme.warning, Brand.accentColor)
        XCTAssertNotEqual(Theme.success, Brand.accentColor)
    }
}
#endif
