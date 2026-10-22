//  CoreUpgradeImportJournalTests.swift
//  `CoreUpgrade.importJournal` end to end against an in-memory core (AITD-535): what moves into
//  the core's journal, what stays in `outbox.json`, and what becomes of the file. A write left
//  behind keeps the upgrade from being marked done, so the file must say exactly what stayed —
//  removed when nothing did, rewritten when some moved, untouched when none could.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class CoreUpgradeImportJournalTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-import-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func entry(_ id: String, kind: String, payload: some Encodable,
                       status: OutboxStatus = .pending) throws -> OutboxEntry {
        OutboxEntry(id: id, kind: kind, payload: try JSONEncoder().encode(payload),
                    clientRequestId: "crid-\(id)", dependsOn: [], status: status, attempts: 0,
                    nextAttemptAt: t0, lastError: nil, createdAt: t0, updatedAt: t0)
    }

    private func createTask(_ id: String, status: OutboxStatus = .pending) throws -> OutboxEntry {
        try entry(id, kind: "createTask",
                  payload: CreateTaskOutboxPayload(title: "Offline \(id)", listIds: ["l1"], tempId: "temp_\(id)"),
                  status: status)
    }

    /// A kind the core's journal never took — it can only stay where it is.
    private func unmovable(_ id: String) throws -> OutboxEntry {
        try entry(id, kind: "createChannel", payload: ["name": "general"])
    }

    private func write(_ entries: [OutboxEntry]) throws {
        try OutboxStore(fileURL: fileURL).save(entries)
    }

    private func journal(_ session: CoreSession) async throws -> JournalStats {
        try await session.run(CoreCommand(kind: "outboxStats"), as: JournalStats.self)
    }

    private func unsent(_ stats: JournalStats) -> Int { stats.pending + stats.running + stats.failed }

    func testEveryQueuedWriteMovesAndTheFileIsRemoved_AITD535() async throws {
        let session = try CoreSearchFixture.session(seeding: [])
        try write([
            try createTask("a"),
            try entry("b", kind: "deleteComment", payload: DeleteCommentOutboxPayload(commentId: "c1")),
        ])

        let leftBehind = CoreUpgrade.importJournal(session, fileURL: fileURL)

        XCTAssertEqual(leftBehind, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "nothing stayed, so the file goes")
        let queued = unsent(try await journal(session))
        XCTAssertEqual(queued, 2, "both writes are in the core's journal")
    }

    func testAWriteThatCannotMoveStaysAndTheFileIsRewrittenWithOnlyIt_AITD535() async throws {
        let session = try CoreSearchFixture.session(seeding: [])
        let stays = try unmovable("x")
        try write([try createTask("a"), stays])

        let leftBehind = CoreUpgrade.importJournal(session, fileURL: fileURL)

        XCTAssertEqual(leftBehind, 1)
        XCTAssertEqual(OutboxStore(fileURL: fileURL).load(), [stays], "the moved write is gone from the file")
        let queued = unsent(try await journal(session))
        XCTAssertEqual(queued, 1)
    }

    /// Nothing moved, so there is nothing to take out of the file — it is left exactly as it was.
    func testWhenNothingMovesTheFileIsLeftAsItWas_AITD535() async throws {
        let session = try CoreSearchFixture.session(seeding: [])
        try write([try unmovable("x")])
        let before = try Data(contentsOf: fileURL)

        let leftBehind = CoreUpgrade.importJournal(session, fileURL: fileURL)

        XCTAssertEqual(leftBehind, 1)
        XCTAssertEqual(try Data(contentsOf: fileURL), before)
        let queued = unsent(try await journal(session))
        XCTAssertEqual(queued, 0)
    }

    /// A write the old Outbox had already dead-lettered is not resurrected in the core, and does
    /// not keep the upgrade from finishing either.
    func testADeadLetteredWriteIsNeitherMovedNorKept_AITD535() async throws {
        let session = try CoreSearchFixture.session(seeding: [])
        try write([try createTask("dead", status: .failedPermanent)])

        let leftBehind = CoreUpgrade.importJournal(session, fileURL: fileURL)

        XCTAssertEqual(leftBehind, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let queued = unsent(try await journal(session))
        XCTAssertEqual(queued, 0)
    }

    /// The core imports each write once, so an upgrade that runs again after a partial move does
    /// not send a write twice.
    func testImportingTheSameWriteTwiceJournalsItOnce_AITD535() async throws {
        let session = try CoreSearchFixture.session(seeding: [])
        let task = try createTask("a")
        try write([task, try unmovable("x")])
        CoreUpgrade.importJournal(session, fileURL: fileURL)
        try write([task, try unmovable("x")])

        CoreUpgrade.importJournal(session, fileURL: fileURL)

        let queued = unsent(try await journal(session))
        XCTAssertEqual(queued, 1)
    }

    func testNoFileIsNothingLeftBehind_AITD535() async throws {
        let session = try CoreSearchFixture.session(seeding: [])

        XCTAssertEqual(CoreUpgrade.importJournal(session, fileURL: fileURL), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
