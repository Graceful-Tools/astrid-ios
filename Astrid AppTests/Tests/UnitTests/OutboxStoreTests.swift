import XCTest
@testable import Astrid_App

/// Tests for the pre-core Outbox journal's file store. astrid-core owns the live outbox now;
/// `OutboxStore` is only the reader `CoreUpgrade.importJournal` uses to move an older build's
/// `outbox.json` into the core (and to rewrite it with whatever stayed behind) — AITD-532.
final class OutboxStoreTests: TempFileTestCase {

    private var tempDir: URL { tempDirectory }

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

        XCTAssertEqual(reloaded, entries, "a fresh store reads what an earlier one wrote")
    }

    func testSaveOverwritesPreviousContents() throws {
        let url = tempDir.appendingPathComponent("outbox.json")
        let store = OutboxStore(fileURL: url)
        try store.save([makeEntry("a"), makeEntry("b")])
        try store.save([makeEntry("c")])
        XCTAssertEqual(store.load().map { $0.id }, ["c"])
    }

    /// A journal that will not decode comes back empty, so the upgrade is not wedged, and the
    /// bytes are kept beside it as `.corrupt` rather than dropped.
    func testLoadOnCorruptFileReturnsEmptyAndKeepsTheBytes_AITD532() throws {
        let url = tempDir.appendingPathComponent("outbox.json")
        let garbage = Data("not a journal".utf8)
        try garbage.write(to: url)

        XCTAssertEqual(OutboxStore(fileURL: url).load(), [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the corrupt file is moved aside")
        let backup = url.appendingPathExtension("corrupt")
        XCTAssertEqual(try Data(contentsOf: backup), garbage)
        XCTAssertEqual(OutboxStore(fileURL: url).load(), [], "a second load starts fresh")
    }
}
