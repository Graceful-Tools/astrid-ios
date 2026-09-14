import XCTest

/// A test case that owns one scratch file URL and one scratch directory under the system
/// temporary directory, both unique per test and removed on tearDown.
///
/// Ten Outbox suites carried a byte-identical `setUpWithError` / `tearDownWithError` pair for
/// this (task 2026-09-13 dedupe review). `tempFile` is NOT created — the store under test
/// creates it; `tempDirectory` IS created, empty, because directory caches expect to exist.
class TempFileTestCase: XCTestCase {
    private(set) var tempFile: URL!
    private(set) var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let stem = "\(type(of: self))-\(UUID().uuidString)"
        tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem).json")
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(stem, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }
}
