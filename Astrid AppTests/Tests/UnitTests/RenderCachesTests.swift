//  RenderCachesTests.swift
//  Task AITD-455 — from the 2026-10-02 performance audit: iOS rebuilt its list rows, its sidebar
//  counts and its date formatters on every redraw, and ImageCache read and decoded on the main
//  actor, swept the cache directory on every store and never told NSCache what an image cost.

import XCTest
@testable import Astrid_App

// MARK: - Memo

@MainActor
final class AITD455MemoTests: XCTestCase {

    func testAITD455MemoComputesOncePerKey() {
        let memo = Memo<Int, String>()
        var calls = 0

        XCTAssertEqual(memo.value(for: 1) { calls += 1; return "first" }, "first")
        XCTAssertEqual(memo.value(for: 1) { calls += 1; return "second" }, "first",
                       "an unchanged key must hand back the remembered value")
        XCTAssertEqual(calls, 1)

        XCTAssertEqual(memo.value(for: 2) { calls += 1; return "third" }, "third",
                       "a changed key must recompute")
        XCTAssertEqual(calls, 2)
    }
}

// MARK: - Date formatters

final class AITD455DateFormatterCacheTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    func testAITD455SameSpecAndZoneShareOneFormatter() {
        let a = DateFormatterCache.formatter(.template("MMM d"), timeZone: utc)
        let b = DateFormatterCache.formatter(.template("MMM d"), timeZone: utc)
        XCTAssertTrue(a === b, "a row must not build a DateFormatter per redraw (AITD-455)")
    }

    func testAITD455TheZoneIsPartOfTheKey() {
        let a = DateFormatterCache.formatter(.template("MMM d"), timeZone: utc)
        let b = DateFormatterCache.formatter(.template("MMM d"), timeZone: tokyo)
        XCTAssertFalse(a === b)
        XCTAssertEqual(a.timeZone, utc)
        XCTAssertEqual(b.timeZone, tokyo, "an all-day date read in the wrong zone prints the wrong day")
    }

    func testAITD455NoZoneMeansTheUsersZone() {
        let f = DateFormatterCache.formatter(.styles(date: .none, time: .short), timeZone: nil)
        XCTAssertEqual(f.timeZone, TimeZone.current)
    }

    func testAITD455ALocaleChangeDropsTheCache() {
        let before = DateFormatterCache.formatter(.styles(date: .medium, time: .none), timeZone: utc)
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        let after = DateFormatterCache.formatter(.styles(date: .medium, time: .none), timeZone: utc)
        XCTAssertFalse(before === after,
                       "a cached formatter keeps the old locale (and 12/24-hour choice) forever")
    }

}

// MARK: - Sidebar and list rows

final class AITD455ViewMemoizationTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path), encoding: .utf8)
    }

}

// MARK: - ImageCache

@MainActor
final class AITD455ImageCacheTests: XCTestCase {

    private func makeJPEG() throws -> (data: Data, image: PlatformImage) {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.7))
        return (data, try XCTUnwrap(PlatformImage(data: data)))
        #else
        throw XCTSkip("UIKit-only fixture")
        #endif
    }

    func testAITD455AnImageCostsItsDecodedBytes() throws {
        let (_, image) = try makeJPEG()
        #if canImport(UIKit)
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(ImageCache.decodedCost(of: image), cg.bytesPerRow * cg.height,
                       "without a cost NSCache's 50 MB totalCostLimit never applies")
        #endif
    }

    func testAITD455AStoreDoesNotRescanTheDirectory() throws {
        let (jpeg, image) = try makeJPEG()
        let url = try XCTUnwrap(URL(string: "https://example.com/aitd455-\(UUID().uuidString).jpg"))
        defer { ImageCache.shared.remove(url: url) }

        let before = ImageCache.shared.sweepCount
        ImageCache.shared.store(jpeg, image: image, for: url)
        XCTAssertEqual(ImageCache.shared.sweepCount, before,
                       "a few KB written must not trigger a full directory scan")
    }
}
