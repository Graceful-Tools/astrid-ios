//  AgentMarkAppearanceTests.swift
//  Regression tests for AITD-604 — "Cannot see copilot logo on dark background".
//
//  Every agent brand mark is drawn straight onto the screen's background, clipped to a circle:
//  the Agent Hub, the default-agent and API-key pickers, list agent settings, comment authors.
//  The other marks are colour (Claude, Gemini, Muse) or ship on an opaque white tile (OpenAI), but
//  `ai-copilot` was a bare black glyph on transparency with no dark variant — so in dark mode it
//  was black on black, and the row showed an empty circle.
//
//  These tests render each mark the way the app does — onto the background it sits on, in each
//  appearance — and measure what is left to see. They check every bundled agent mark, not only
//  Copilot, so the next single-colour brand mark fails here rather than on a phone at night.

import XCTest
import UIKit
@testable import Astrid_App

final class AgentMarkAppearanceTests: XCTestCase {

    /// The agent slugs the app brands, through the real mapping both platforms use.
    private let brandedSlugs = ["claude", "openai", "gemini", "copilot", "muse", "openclaw"]

    /// A pixel "can be seen" when it differs from the background by at least this contrast ratio.
    /// Deliberately a visibility floor, not WCAG's 3:1 for graphics: Claude's brand copper on white
    /// is about 2.2:1 and is plainly visible, while black on the dark background is about 1.0–1.2:1.
    private let visibleContrast = 1.5

    /// At least this share of the mark's frame must be visible. The thinnest mark (Copilot's
    /// outline) covers roughly a third of its frame once rendered; an invisible one covers none.
    private let minimumVisibleShare = 0.10

    // MARK: - AITD-604

    /// AITD-604: the Copilot mark is visible on the dark background.
    func testCopilotMarkIsVisibleInDarkMode() throws {
        let share = try visibleShare(of: "ai-copilot", in: .dark)
        XCTAssertGreaterThanOrEqual(share, minimumVisibleShare,
                                    "ai-copilot is \(percent(share)) visible on the dark background — black on black")
    }

    /// The fix must not trade one appearance for the other: a white mark on a white background is
    /// the same bug the other way round.
    func testCopilotMarkIsStillVisibleInLightMode() throws {
        let share = try visibleShare(of: "ai-copilot", in: .light)
        XCTAssertGreaterThanOrEqual(share, minimumVisibleShare,
                                    "ai-copilot is \(percent(share)) visible on the light background")
    }

    /// Every bundled agent mark is visible in both appearances.
    func testEveryAgentMarkIsVisibleInBothAppearances() throws {
        let assets = Set(brandedSlugs.compactMap(User.brandImageAsset(forAgentSlug:)))
        XCTAssertEqual(assets.count, brandedSlugs.count, "a branded slug no longer maps to a mark")
        for asset in assets.sorted() {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let share = try visibleShare(of: asset, in: style)
                XCTAssertGreaterThanOrEqual(share, minimumVisibleShare,
                                            "\(asset) is \(percent(share)) visible in \(style == .dark ? "dark" : "light") mode")
            }
        }
    }

    // MARK: - Rendering

    /// Renders `asset` as the app draws it — onto `systemBackground` for `style` — and returns the
    /// share of pixels whose contrast with that background reaches `visibleContrast`.
    private func visibleShare(of asset: String, in style: UIUserInterfaceStyle) throws -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let named = try XCTUnwrap(UIImage(named: asset, in: .main, compatibleWith: traits),
                                  "\(asset) is missing from the app bundle")
        // Resolve the appearance variant explicitly; drawing does not consult the trait passed above.
        let image = named.imageAsset?.image(with: traits) ?? named
        let background = UIColor.systemBackground.resolvedColor(with: traits)

        let side = 64
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.scale = 1
        format.opaque = true
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            background.setFill()
            context.fill(frame)
            image.draw(in: frame)
        }

        let pixels = try rgba(of: rendered, side: side)
        let backgroundLuminance = luminance(of: background)
        var visible = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let l = luminance(Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
            if contrast(l, backgroundLuminance) >= visibleContrast { visible += 1 }
        }
        return Double(visible) / Double(side * side)
    }

    private func rgba(of image: UIImage, side: Int) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        XCTAssertTrue(drawn, "could not read the rendered pixels")
        return pixels
    }

    // MARK: - WCAG relative luminance and contrast

    private func luminance(of color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return luminance(Double(r), Double(g), Double(b))
    }

    private func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}
