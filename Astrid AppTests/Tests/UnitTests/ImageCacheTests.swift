//  ImageCacheTests.swift
//  Task AITD-345 — ImageCache decoded on the main thread, re-encoded every image as PNG, and
//  never evicted from disk.

import XCTest
@testable import Astrid_App

@MainActor
final class ImageCacheTests: XCTestCase {

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ListImageCache", isDirectory: true)
    }

    private func diskURL(for url: URL) -> URL {
        let filename = url.absoluteString
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent(filename)
    }

    /// A small real JPEG — the point of the encoding test is that JPEG bytes stay JPEG bytes.
    private func makeJPEG() throws -> (data: Data, image: PlatformImage) {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.7))
        return (data, try XCTUnwrap(PlatformImage(data: data)))
        #else
        throw XCTSkip("UIKit-only fixture")
        #endif
    }

    // MARK: - No PNG re-encode (finding 2)

    func testTheBytesOnDiskAreTheBytesWeWereServed() throws {
        let (jpeg, image) = try makeJPEG()
        let url = try XCTUnwrap(URL(string: "https://example.com/aitd345-\(UUID().uuidString).jpg"))
        defer { ImageCache.shared.remove(url: url) }

        ImageCache.shared.store(jpeg, image: image, for: url)

        let onDisk = try Data(contentsOf: diskURL(for: url))
        XCTAssertEqual(onDisk, jpeg,
                       "the cache stored a PNG re-encode of every image, so a 200 KB JPEG avatar "
                       + "became a multi-megabyte PNG on disk (AITD-345)")
    }

    func testAJPEGIsNotInflatedIntoAPNG() throws {
        let (jpeg, image) = try makeJPEG()
        let url = try XCTUnwrap(URL(string: "https://example.com/aitd345-\(UUID().uuidString).jpg"))
        defer { ImageCache.shared.remove(url: url) }

        ImageCache.shared.store(jpeg, image: image, for: url)
        let onDisk = try Data(contentsOf: diskURL(for: url))

        // A PNG starts with the 8-byte signature 89 50 4E 47 0D 0A 1A 0A.
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertNotEqual(Array(onDisk.prefix(8)), pngSignature, "still re-encoding to PNG")
        XCTAssertLessThanOrEqual(onDisk.count, jpeg.count,
                                 "storing the served bytes can never be larger than the served bytes")
    }

    func testTheStoredImageIsAvailableFromMemoryImmediately() throws {
        let (jpeg, image) = try makeJPEG()
        let url = try XCTUnwrap(URL(string: "https://example.com/aitd345-\(UUID().uuidString).jpg"))
        defer { ImageCache.shared.remove(url: url) }

        ImageCache.shared.store(jpeg, image: image, for: url)
        XCTAssertNotNil(ImageCache.shared.memoryImage(for: url))
    }

    func testMemoryImageDoesNotReachDisk() throws {
        // The fast path must be memory-ONLY: a disk hit here would be the render-time file read
        // and decode this task is about.
        let (jpeg, image) = try makeJPEG()
        let url = try XCTUnwrap(URL(string: "https://example.com/aitd345-\(UUID().uuidString).jpg"))
        defer { ImageCache.shared.remove(url: url) }

        ImageCache.shared.store(jpeg, image: image, for: url)
        ImageCache.shared.clearMemoryCache()

        XCTAssertNil(ImageCache.shared.memoryImage(for: url),
                     "it is on disk, but memoryImage must not go and read it")
        XCTAssertNotNil(ImageCache.shared.get(url: url),
                        "the synchronous getter still reads disk — that is what it is for")
    }

    // MARK: - Disk eviction (finding 3)

    func testTheDiskCacheEvictsDownToItsCap() throws {
        let (jpeg, image) = try makeJPEG()
        var urls: [URL] = []
        for index in 0..<6 {
            let url = try XCTUnwrap(URL(string: "https://example.com/aitd345-evict-\(index)-\(UUID().uuidString).jpg"))
            urls.append(url)
            ImageCache.shared.store(jpeg, image: image, for: url)
        }
        defer { urls.forEach { ImageCache.shared.remove(url: $0) } }

        // Squeeze to roughly two files' worth and confirm the directory really shrinks.
        ImageCache.shared.enforceDiskLimit(cap: jpeg.count * 2)

        let remaining = urls.filter { FileManager.default.fileExists(atPath: diskURL(for: $0).path) }
        XCTAssertLessThanOrEqual(remaining.count, 2,
                                 "the disk cache only ever shrank on sign-out before (AITD-345)")
        XCTAssertFalse(remaining.isEmpty, "eviction must not empty the cache wholesale")
    }
}

