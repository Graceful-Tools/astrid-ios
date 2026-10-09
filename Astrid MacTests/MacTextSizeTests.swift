//  MacTextSizeTests.swift
//  Regression guard for AITD-469 — "[MAC] add ability to increase font size in the app. respond
//  to accessibility settings on the mac".
//
//  SwiftUI's Dynamic Type is inert on macOS: `.dynamicTypeSize(.accessibility3)` renders `.body`
//  and `.system(size:)` at exactly the size `.large` does (measured 2026-10-09 with
//  ImageRenderer), and System Settings' Text size slider only reaches Apple's own apps. So the
//  Mac app had no way to grow its text at all. The fix is an app-wide text size (View ▸ Bigger /
//  Smaller / Actual Size, ⌘+ ⌘− ⌘0, and Settings) that every Mac font is routed through.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

@MainActor
final class MacTextSizeTests: XCTestCase {

    /// A fresh, empty suite per test — never the user's real setting.
    private lazy var defaults: UserDefaults = {
        let suite = "MacTextSizeTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }()

    // MARK: - The setting

    func testDefaultsToActualSize() {
        XCTAssertEqual(MacTextSize(defaults: defaults).scale, 1.0)
    }

    func testBiggerAndSmallerStepAndPersist() {
        let size = MacTextSize(defaults: defaults)
        size.bigger()
        XCTAssertGreaterThan(size.scale, 1.0)
        XCTAssertEqual(MacTextSize(defaults: defaults).scale, size.scale, "survives a relaunch")
        size.smaller(); size.smaller()
        XCTAssertLessThan(size.scale, 1.0)
        size.reset()
        XCTAssertEqual(size.scale, 1.0)
        XCTAssertFalse(size.canReset)
    }

    func testClampsAtBothEnds() {
        let size = MacTextSize(defaults: defaults)
        for _ in 0..<20 { size.bigger() }
        XCTAssertEqual(size.scale, MacTextSize.steps.last)
        XCTAssertFalse(size.canGrow)
        for _ in 0..<20 { size.smaller() }
        XCTAssertEqual(size.scale, MacTextSize.steps.first)
        XCTAssertFalse(size.canShrink)
    }

    func testAStoredValueOffTheLadderSnapsToTheNearestStep() {
        defaults.set(1.33, forKey: MacTextSize.defaultsKey)
        XCTAssertTrue(MacTextSize.steps.contains(MacTextSize(defaults: defaults).scale))
    }

    // MARK: - The fonts

    func testActualSizeIsTodaysFontExactly() {
        // 100% must not move a single glyph: the default look is what every earlier fix tuned.
        XCTAssertEqual(MacFont.caption.font(scale: 1), Font.caption)
        XCTAssertEqual(MacFont.headline.font(scale: 1), Font.headline)
        XCTAssertEqual(MacFont.title2.bold().font(scale: 1), Font.title2.bold())
        XCTAssertEqual(MacFont.system(size: 12).font(scale: 1), Font.system(size: 12))
        XCTAssertEqual(MacTypography.detailBody.font(scale: 1),
                       Font.system(size: MacTypography.detailBodySize, weight: .regular))
    }

    func testOtherSizesScaleThePointSize() {
        XCTAssertEqual(MacFont.system(size: 12, weight: .semibold).font(scale: 1.5),
                       Font.system(size: 18, weight: .semibold))
        XCTAssertEqual(MacTypography.rowTitle.font(scale: 2),
                       Font.system(size: MacTypography.rowTitleSize * 2, weight: .medium))
        XCTAssertNotEqual(MacFont.caption.font(scale: 1.5), Font.caption,
                          "a text style has to grow too — it is most of the app's text")
        XCTAssertEqual(MacFont.pointSize(of: .caption, scale: 2),
                       NSFont.preferredFont(forTextStyle: .caption1).pointSize * 2)
    }

    // MARK: - Nothing bypasses it

    /// A raw `.font(.caption)` in a Mac view ignores the setting, and there were 160 of them.
    /// Glyphs drawn to fit a fixed frame (`size * ratio`) are the exception: they scale with
    /// their frame, not with the text.
    func testNoMacViewSetsAFontThatIgnoresTheTextSize() throws {
        let root = RepositoryLocator.root.appendingPathComponent("Astrid Mac")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "MacTextSize.swift" }
        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            // `.font(scale:)` is MacFont resolving itself, not a view setting a font.
            for (i, line) in lines.enumerated()
            where line.range(of: #"\.font\((?!scale:)"#, options: .regularExpression) != nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || line.contains("size: size *") { continue }
                offenders.append("\(file.lastPathComponent):\(i + 1): \(trimmed)")
            }
        }
        XCTAssertEqual(offenders, [], "Use .macFont(...) so the text size reaches it")
    }
}
#endif
