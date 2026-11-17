//  MacHeaderBandUITests.swift
//  The window's header band runs across the sidebar too (ADEV-66).
//
//  Jon: "header color should extend to the left panel on mac". The toolbar band behind the list's
//  title was the system's unthemed material and stopped at the sidebar divider; the sidebar's part
//  of the title bar was painted the sidebar's navy. A unit test cannot see this — the colours are
//  resolved at render time — so this samples the real window's pixels on both sides of the divider.

import XCTest
import AppKit

final class MacHeaderBandUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// One pixel of a screenshot, at a point measured from the window's top-left in points.
    private struct Sampler {
        let bitmap: NSBitmapImageRep
        let scale: CGFloat

        init?(_ shot: XCUIScreenshot, pointWidth: CGFloat) {
            guard let tiff = shot.image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff), pointWidth > 0 else { return nil }
            bitmap = rep
            scale = CGFloat(rep.pixelsWide) / pointWidth
        }

        func rgb(x: CGFloat, y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
            let px = Int((x * scale).rounded()), py = Int((y * scale).rounded())
            guard px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh,
                  let c = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return nil }
            return (c.redComponent, c.greenComponent, c.blueComponent)
        }
    }

    private func distance(_ a: (r: CGFloat, g: CGFloat, b: CGFloat),
                          _ b: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
    }

    /// In each theme, the band at the top of the sidebar is the band at the top of the list.
    @MainActor
    func testTheHeaderBandRunsAcrossTheSidebar_ADEV66() throws {
        for mode in ["dark", "light", "ocean"] {
            let app = MacUITestLaunch.makeApp(arguments: ["-themeMode", mode])
            app.launch()
            XCTAssertTrue(MacUITestLaunch.enterShell(app).exists, "\(mode): the shell never appeared")
            app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch.click()
            app.activate()

            let window = app.windows.firstMatch
            let sidebar = app.descendants(matching: .any).matching(identifier: "sidebar.lists").firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
            let shot = window.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "header-band-\(mode)"
            attachment.lifetime = .keepAlways
            add(attachment)

            let frame = window.frame
            let sampler = try XCTUnwrap(Sampler(shot, pointWidth: frame.width))
            let sidebarWidth = sidebar.frame.maxX - frame.minX
            // Clear of the window buttons (left) and the sidebar toggle (right of the sidebar), and
            // of the list title and toolbar controls, which sit in the middle of the band's height.
            let y: CGFloat = 6
            let left = try XCTUnwrap(sampler.rgb(x: sidebarWidth * 0.55, y: y))
            let right = try XCTUnwrap(sampler.rgb(x: sidebarWidth + (frame.width - sidebarWidth) * 0.5, y: y))
            XCTAssertLessThan(distance(left, right), 0.04,
                              "\(mode): the sidebar's header \(left) should be the list's header band \(right)")
            app.terminate()
        }
    }
}
