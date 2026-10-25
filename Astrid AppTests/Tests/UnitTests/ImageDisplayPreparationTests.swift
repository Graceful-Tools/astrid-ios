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

    // MARK: - A half-written cache file (AITD-551, second cause)

    /// The palette avatars were not the whole story: after that fix a 200-action run still logged
    /// -17102 five times on five threads, and a breakpoint on the log put every one in `getAsync`
    /// for `astrid.cc/icons/default_list_2.png` — a 65×65 RGBA PNG that prepares fine on its own.
    /// What those rows read was a file another row's fetch was still writing: `store` wrote
    /// non-atomically, and `UIImage(data:)` accepts a PNG from its header alone, so the truncated
    /// bytes only failed later, in the decompressor. A partial file must read as a miss (and be
    /// removed, so the next load refetches it) rather than be handed to UIKit to fail on.
    func testATruncatedCacheFileIsAMissNotADecompressorError_AITD551() async throws {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let full = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 65, height: 65), format: format).image { ctx in
            for row in 0..<65 {
                UIColor(hue: CGFloat(row) / 65, saturation: 1, brightness: 1, alpha: 0.8).setFill()
                ctx.fill(CGRect(x: 0, y: row, width: 65, height: 1))
            }
        }.pngData())
        let truncated = full.prefix(full.count / 2)
        XCTAssertNotNil(UIImage(data: truncated), "fixture: UIKit accepts the half-written PNG from its header")

        let url = try XCTUnwrap(URL(string: "https://example.com/aitd551-\(UUID().uuidString).png"))
        defer { ImageCache.shared.remove(url: url) }
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListImageCache", isDirectory: true)
            .appendingPathComponent(url.absoluteString.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_"))
        try Data(truncated).write(to: file)

        let read = await ImageCache.shared.getAsync(url: url)
        XCTAssertNil(read, "AITD-551: a partial cache file must be a miss, not an image UIKit fails to decompress")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "the partial file must go, or every launch reads it again")
        #else
        throw XCTSkip("UIKit-only")
        #endif
    }
}
