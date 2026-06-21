import XCTest
@testable import Astrid_App

/// Tests for the Outbox journal's durable store. The journal must survive app
/// relaunch (offline writes can't be lost), so it persists atomically to disk.
final class OutboxStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeEntry(_ id: String) -> OutboxEntry {
        OutboxEntry(
            id: id, kind: "createComment", payload: Data("{\"x\":1}".utf8),
            clientRequestId: "crid-\(id)", dependsOn: [], status: .pending,
            attempts: 0, nextAttemptAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastError: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testLoadOnMissingFileReturnsEmpty() {
        let store = OutboxStore(fileURL: tempDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(store.load(), [])
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = tempDir.appendingPathComponent("outbox.json")
        let store = OutboxStore(fileURL: url)
        let entries = [makeEntry("a"), makeEntry("b")]

        try store.save(entries)
        let reloaded = OutboxStore(fileURL: url).load()  // fresh instance reads from disk

        XCTAssertEqual(reloaded, entries, "journal must survive a relaunch (new store instance)")
    }

    func testSaveOverwritesPreviousContents() throws {
        let url = tempDir.appendingPathComponent("outbox.json")
        let store = OutboxStore(fileURL: url)
        try store.save([makeEntry("a"), makeEntry("b")])
        try store.save([makeEntry("c")])
        XCTAssertEqual(store.load().map { $0.id }, ["c"])
    }
}
