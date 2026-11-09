//  MacAgentMarkAppearanceTests.swift
//  Regression tests for AITD-604 — "Cannot see copilot logo on dark background", on the Mac.
//
//  The Mac draws an agent's brand mark straight onto the window background (the chat panel's
//  author avatar, through `User.agentBrandImageAsset`). Its catalog carries its own copy of
//  `ai-copilot`, which was the same bare black glyph as iOS with no dark variant: black on the dark
//  window background. These tests render each mark onto that background under each appearance and
//  measure what is left to see — every bundled agent mark, not only Copilot.

import XCTest
import AppKit
@testable import Astrid_Mac

final class MacAgentMarkAppearanceTests: XCTestCase {

    /// The agent slugs the app brands, through the real mapping both platforms use.
    private let brandedSlugs = ["claude", "openai", "gemini", "copilot", "muse", "openclaw"]

    /// A visibility floor, not WCAG's 3:1 — see `AgentMarkAppearanceTests` on iOS for why.
    private let visibleContrast = 1.5
    private let minimumVisibleShare = 0.10

    /// AITD-604: the Copilot mark is visible on the dark window background.
    func testCopilotMarkIsVisibleInDarkMode() throws {
        let share = try visibleShare(of: "ai-copilot", appearance: .darkAqua)
        XCTAssertGreaterThanOrEqual(share, minimumVisibleShare,
                                    "ai-copilot is \(percent(share)) visible on the dark window — black on black")
    }

    /// Every bundled agent mark is visible in both appearances.
    func testEveryAgentMarkIsVisibleInBothAppearances() throws {
        let assets = Set(brandedSlugs.compactMap(User.brandImageAsset(forAgentSlug:)))
        XCTAssertEqual(assets.count, brandedSlugs.count, "a branded slug no longer maps to a mark")
        for asset in assets.sorted() {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let share = try visibleShare(of: asset, appearance: appearance)
                XCTAssertGreaterThanOrEqual(share, minimumVisibleShare,
                                            "\(asset) is \(percent(share)) visible under \(appearance.rawValue)")
            }
        }
    }

    // MARK: - Rendering

    private func visibleShare(of asset: String, appearance name: NSAppearance.Name) throws -> Double {
        let image = try XCTUnwrap(NSImage(named: asset), "\(asset) is missing from the Mac bundle")
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        let side = 64
        let frame = NSRect(x: 0, y: 0, width: side, height: side)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: side * 4, bitsPerPixel: 32))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))

        var background = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            // Resolve the dynamic colour and the image variant under this appearance.
            background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .black
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            background.setFill()
            frame.fill()
            image.draw(in: frame)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }

        let backgroundLuminance = luminance(of: background)
        var visible = 0
        for x in 0..<side {
            for y in 0..<side {
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if contrast(luminance(of: pixel), backgroundLuminance) >= visibleContrast { visible += 1 }
            }
        }
        return Double(visible) / Double(side * side)
    }

    // MARK: - WCAG relative luminance and contrast

    private func luminance(of color: NSColor) -> Double {
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    }

    private func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}
