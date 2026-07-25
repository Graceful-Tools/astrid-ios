//  MacAppIconTests.swift
//  Astrid for Mac — regression: the Mac app had no app icon (empty AppIcon.appiconset).
//
//  Asserts against the BUILT HOST BUNDLE (the test host is the app), not the repo tree: the old
//  version listed the repo directory in ~/Documents via #filePath, which hangs forever inside
//  tccd when the app's Documents-folder TCC grant is stale (e.g. after an ad-hoc-signed variant
//  with the same bundle id invalidated it) — a sandboxed, headless test host can't prompt.
//  Checking the product is also the stronger claim: the icon actually ships in the app.

import XCTest

final class MacAppIconTests: XCTestCase {

    /// The built app must contain the compiled macOS app icon.
    func testMacAppIconIsPopulated() throws {
        let bundle = Bundle.main   // unit tests are hosted by Astrid Mac.app

        // actool compiles AppIcon.appiconset → Resources/AppIcon.icns for the app-icon set.
        let icns = bundle.url(forResource: "AppIcon", withExtension: "icns")
        XCTAssertNotNil(icns, "Built app must contain AppIcon.icns — the app was shipping with no icon")
        if let icns {
            let size = ((try? FileManager.default.attributesOfItem(atPath: icns.path))?[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 1_000, "AppIcon.icns must not be empty")
        }

        // Info.plist must reference the icon set.
        let iconName = (bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String)
        XCTAssertEqual(iconName, "AppIcon", "Info.plist must declare the AppIcon set")
    }
}
