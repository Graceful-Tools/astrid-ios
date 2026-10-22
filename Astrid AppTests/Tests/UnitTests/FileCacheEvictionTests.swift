//  FileCacheEvictionTests.swift
//  Task AITD-344 — the downloaded-attachment cache grew without bound.

import XCTest
@testable import Astrid_App

final class FileCacheEvictionTests: XCTestCase {

    private func entry(_ id: String, _ size: Int, _ minutesAgo: Int) -> FileCacheEntry {
        FileCacheEntry(id: id, size: size, lastAccess: Date(timeIntervalSince1970: 10_000_000 - Double(minutesAgo) * 60))
    }

    func testNothingIsEvictedUnderTheCap() {
        let entries = [entry("a", 10, 5), entry("b", 20, 1)]
        XCTAssertEqual(FileCacheEviction.idsToEvict(entries, cap: 100), [],
                       "the common case, and it has to stay cheap — this runs after every write")
    }

    func testNothingIsEvictedExactlyAtTheCap() {
        XCTAssertEqual(FileCacheEviction.idsToEvict([entry("a", 50, 1), entry("b", 50, 2)], cap: 100), [])
    }

    func testTheLeastRecentlyAccessedGoesFirst() {
        let entries = [
            entry("recent", 60, 1),
            entry("ancient", 60, 500),
            entry("middling", 60, 50),
        ]
        // 180 total, cap 120 → one must go, and it must be the one nobody has opened in ages.
        XCTAssertEqual(FileCacheEviction.idsToEvict(entries, cap: 120), ["ancient"])
    }

    func testItEvictsAsManyAsNeededAndNoMore() {
        let entries = (0..<10).map { entry("f\($0)", 10, 100 - $0) }   // f0 oldest … f9 newest
        // 100 total, cap 55 → drop 45+ worth, oldest first: f0…f4 is 50, which is the first
        // point at or below the cap.
        XCTAssertEqual(FileCacheEviction.idsToEvict(entries, cap: 55), ["f0", "f1", "f2", "f3", "f4"])
    }

    func testOneOversizedFileCanBeEvictedToGetUnderTheCap() {
        let entries = [entry("huge", 500, 10), entry("small", 5, 1)]
        XCTAssertEqual(FileCacheEviction.idsToEvict(entries, cap: 100), ["huge"])
    }

    func testEverythingGoesWhenNothingWouldFit() {
        let entries = [entry("a", 100, 2), entry("b", 100, 1)]
        XCTAssertEqual(FileCacheEviction.idsToEvict(entries, cap: 0), ["a", "b"])
    }

    func testTiesBreakDeterministically() {
        let same = Date(timeIntervalSince1970: 1)
        let entries = [
            FileCacheEntry(id: "b", size: 100, lastAccess: same),
            FileCacheEntry(id: "a", size: 100, lastAccess: same),
        ]
        XCTAssertEqual(FileCacheEviction.idsToEvict(entries, cap: 100), ["a"],
                       "same age must not mean an arbitrary, flaky choice")
    }

    func testAnEmptyCacheIsFine() {
        XCTAssertEqual(FileCacheEviction.idsToEvict([], cap: 100), [])
    }
}

/// The filesystem half of AITD-344: the policy is pure and tested above, but "does the sweep
/// actually read sizes and delete the right files" needs real files on disk.
final class DownloadCacheSweepTests: TempFileTestCase {

    private var directory: URL { tempDirectory.appendingPathComponent("cache", isDirectory: true) }
    private var previewRoot: URL { tempDirectory.appendingPathComponent("previews", isDirectory: true) }

    /// The real cache over the temp directory — the tests drive production, not a copy of its
    /// directory walk (AITD-536).
    private func cache(cap: Int = 100_000) -> DownloadedAttachmentCache {
        DownloadedAttachmentCache(directory: directory, previewRoot: previewRoot, byteLimit: cap)
    }

    /// Write `bytes` to `name`, backdating its timestamps so age is controllable.
    private func write(_ name: String, bytes: Int, minutesAgo: Int) throws {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        let when = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)
    }

    private func survivors() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    func testTheOldestFilesAreTheOnesRemovedOnceTheCapIsPassed() throws {
        let cache = cache(cap: 100_000)
        try write("old", bytes: 40_000, minutesAgo: 600)
        try write("middle", bytes: 40_000, minutesAgo: 300)
        try write("fresh", bytes: 40_000, minutesAgo: 1)

        cache.enforceLimit()

        XCTAssertEqual(try survivors(), ["middle", "fresh"],
                       "120 KB over a 100 KB cap: the oldest goes and the rest stay")
    }

    func testAStoreOverTheCapSweepsTheOldest() throws {
        let cache = cache(cap: 100_000)
        try write("old", bytes: 40_000, minutesAgo: 600)
        try write("middle", bytes: 40_000, minutesAgo: 300)

        cache.store(Data(repeating: 0x42, count: 40_000), for: "new")

        XCTAssertEqual(try survivors(), ["middle", "new"], "every write sweeps, not only launch")
    }

    func testAnUnderCapDirectoryIsLeftEntirelyAlone() throws {
        let cache = cache(cap: 1_000)
        try write("a", bytes: 10, minutesAgo: 999)
        try write("b", bytes: 10, minutesAgo: 1)
        cache.enforceLimit()
        XCTAssertEqual(try survivors(), ["a", "b"])
    }

    /// AITD-344's other half: preview paths keyed only by NAME collided, so two attachments both
    /// called "photo.png" resolved to one file. Harmless-looking until the downloads run
    /// concurrently, at which point one task is copying over what another is reading.
    func testTwoFilesWithTheSameNameGetDistinctPreviewPaths() {
        let cache = cache()
        let first = cache.previewURL(fileId: "file-aaa", fileName: "photo.png")
        let second = cache.previewURL(fileId: "file-bbb", fileName: "photo.png")

        XCTAssertNotEqual(first, second, "same name, different files — these must not share a path")
        XCTAssertEqual(first.lastPathComponent, "photo.png",
                       "the display name survives, so QuickLook still picks a previewer")
        XCTAssertEqual(second.lastPathComponent, "photo.png")
    }

    func testAHostileFileIdCannotEscapeThePreviewDirectory() {
        // The id is server-supplied, so it goes through the same sanitiser as the name.
        let leaf = AttachmentFileName.sanitized("../../../etc/passwd")
        XCTAssertFalse(leaf.contains("/"))
        XCTAssertEqual(leaf, "passwd")
        let url = cache().previewURL(fileId: "../../../etc/passwd", fileName: "x.txt")
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(previewRoot.standardizedFileURL.path + "/"),
                      "the preview stays inside its root: \(url.path)")
    }
}
