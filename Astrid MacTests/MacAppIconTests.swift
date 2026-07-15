//  MacAppIconTests.swift
//  Astrid for Mac — regression: the Mac app had no app icon (empty AppIcon.appiconset).
//  RED before this fix (only Contents.json, no images); GREEN once macOS icon PNGs exist.

import XCTest

final class MacAppIconTests: XCTestCase {

    /// The Mac AppIcon asset must contain macOS icon images (not just Contents.json).
    func testMacAppIconIsPopulated() throws {
        // repo root = two directories up from this test file (…/Astrid MacTests/<file>).
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconset = repoRoot.appendingPathComponent("Astrid Mac/Assets.xcassets/AppIcon.appiconset")

        let contents = try FileManager.default.contentsOfDirectory(atPath: iconset.path)
        let pngs = contents.filter { $0.hasSuffix(".png") }

        XCTAssertGreaterThanOrEqual(pngs.count, 5,
            "Mac AppIcon.appiconset must contain icon images — the app was shipping with no icon.")

        // Contents.json must reference macOS idiom entries.
        let json = try String(contentsOf: iconset.appendingPathComponent("Contents.json"), encoding: .utf8)
        XCTAssertTrue(json.contains("\"idiom\" : \"mac\"") || json.contains("\"idiom\":\"mac\""),
            "AppIcon Contents.json must declare macOS ('mac') idiom images.")
    }
}
