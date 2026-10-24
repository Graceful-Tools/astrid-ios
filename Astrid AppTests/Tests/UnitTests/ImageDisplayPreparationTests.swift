//  ImageDisplayPreparationTests.swift
//  AITD-551 — the monkey logged "Error -17102 decompressing image -- possibly corrupt" in bursts.
//
//  The agent avatars (`ai-agents/claude.png`, `gemini.png`) are 8-bit COLORMAP PNGs. They decode,
//  but UIKit's `preparingForDisplay()` cannot decompress a palette image: it logs -17102 and
//  returns nil. Every row showing that avatar missed memory and ran its own disk read, so a list
//  of agent-assigned tasks logged it once per row, on as many threads, within milliseconds.

import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Astrid_App

final class ImageDisplayPreparationTests: XCTestCase {

    /// A 4×4 palette PNG — the shape of the agent avatars, built here rather than shipped.
    private func makeIndexedPNG() throws -> Data {
        let table: [UInt8] = [255, 0, 0, 0, 0, 255]               // red, blue
        let base = CGColorSpaceCreateDeviceRGB()
        let indexed = try XCTUnwrap(CGColorSpace(indexedBaseSpace: base, last: 1, colorTable: table))
        let pixels: [UInt8] = (0..<16).map { UInt8($0 % 2) }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let cg = try XCTUnwrap(CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 8,
                                       bytesPerRow: 4, space: indexed, bitmapInfo: [],
                                       provider: provider, decode: nil, shouldInterpolate: false,
                                       intent: .defaultIntent))
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    func testAPaletteImageIsPreparedWithoutFallingBackToTheLazyDecode_AITD551() throws {
        #if canImport(UIKit)
        let image = try XCTUnwrap(UIImage(data: try makeIndexedPNG()))
        XCTAssertEqual(image.cgImage?.colorSpace?.model, .indexed, "fixture is a palette image")

        let prepared = ImageCache.preparedForDisplay(image)
        XCTAssertEqual(prepared.cgImage?.colorSpace?.model, .rgb,
                       "AITD-551: a palette image must be drawn into an RGB bitmap, not handed back undecoded")
        XCTAssertEqual(prepared.size, image.size)
        XCTAssertEqual(prepared.scale, image.scale)
        #else
        throw XCTSkip("UIKit-only")
        #endif
    }

    /// An ordinary RGB(A) image still goes through UIKit's own preparation.
    func testAnRGBImageIsStillPrepared_AITD551() throws {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let data = try XCTUnwrap(renderer.image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData())
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(ImageCache.preparedForDisplay(image).cgImage?.colorSpace?.model, .rgb)
        #else
        throw XCTSkip("UIKit-only")
        #endif
    }
}
