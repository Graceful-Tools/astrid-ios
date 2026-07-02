import XCTest
@testable import Astrid_App

/// Matrix coverage for comment sync through the Outbox (the user's repro: two
/// online comments with attachments — the first one's chain was starved by the
/// legacy uploader and disappeared). At this level we assert the CHAINS are
/// correct: two back-to-back upload→comment chains complete independently with
/// their own fileIds, and the offline-created-task variant orders correctly.
final class OutboxCommentMatrixTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-matrix-\(UUID().uuidString).json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: url) }

    private func entry(_ id: String, kind: String, payload: [String: String] = [:],
                       dependsOn: [String] = []) -> OutboxEntry {
        OutboxEntry(id: id, kind: kind,
                    payload: (try? JSONEncoder().encode(payload)) ?? Data(),
                    clientRequestId: "c-\(id)", dependsOn: dependsOn, status: .pending,
                    attempts: 0, nextAttemptAt: t0, lastError: nil, createdAt: t0, updatedAt: t0)
    }

    /// Two comments, each with its own attachment, sent back-to-back while
    /// online. Both chains must complete and each comment must receive ITS OWN
    /// upload's fileId — chain 1 must not be starved or cross-wired by chain 2.
    func testTwoBackToBackAttachmentCommentChainsBothComplete() async {
        let posted = PostedCommentsBox()
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: url),
            handlers: [
                "upload": { entry, _ in
                    let p = (try? JSONDecoder().decode([String: String].self, from: entry.payload)) ?? [:]
                    return .success(["fileId": "real-\(p["photo"] ?? "?")"])
                },
                "comment": { entry, context in
                    await posted.record(entry.id, fileId: context.value("fileId"))
                    return .success([:])
                }
            ],
            now: { self.t0 }
        )

        await runner.enqueueBatch([
            entry("upA", kind: "upload", payload: ["photo": "A"]),
            entry("cA", kind: "comment", dependsOn: ["upA"])
        ])
        await runner.enqueueBatch([
            entry("upB", kind: "upload", payload: ["photo": "B"]),
            entry("cB", kind: "comment", dependsOn: ["upB"])
        ])

        let snap = await runner.snapshot()
        XCTAssertTrue(snap.allSatisfy { $0.status == .completed },
                      "both chains complete — nothing stranded: \(snap.map { "\($0.id)=\($0.status)" })")
        let byId = await posted.all()
        XCTAssertEqual(byId["cA"], "real-A", "first comment keeps its OWN attachment")
        XCTAssertEqual(byId["cB"], "real-B", "second comment keeps its OWN attachment")
    }

    /// Offline-created task + attachment comment: createTask → upload → comment.
    /// The comment resolves the real task id from the create's output and the
    /// real file id from the upload's output (CommentOutboxResolver semantics).
    func testOfflineCreatedTaskWithAttachmentCommentResolvesBothIds() async {
        let posted = PostedCommentsBox()
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: url),
            handlers: [
                "createTask": { _, _ in .success(["taskId": "real-task-1"]) },
                "upload": { _, _ in .success(["fileId": "real-file-1"]) },
                "comment": { entry, context in
                    let resolved = CommentOutboxResolver.resolve(
                        payloadTaskId: "temp_task", payloadFileId: "temp_file", context: context)
                    await posted.record(entry.id, fileId: "\(resolved.taskId)|\(resolved.fileId ?? "nil")")
                    return .success([:])
                }
            ],
            now: { self.t0 }
        )

        await runner.enqueueBatch([
            entry("t", kind: "createTask"),
            entry("u", kind: "upload"),
            entry("c", kind: "comment", dependsOn: ["t", "u"])
        ])

        let snap = await runner.snapshot()
        XCTAssertTrue(snap.allSatisfy { $0.status == .completed })
        let byId = await posted.all()
        XCTAssertEqual(byId["c"], "real-task-1|real-file-1",
                       "comment posts against the REAL task id with the REAL file id")
    }

    /// Plain comment (no attachment) enqueued while the runner also has an
    /// unrelated failing chain — the healthy comment is unaffected.
    func testPlainCommentUnaffectedByUnrelatedFailedChain() async {
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: url),
            handlers: [
                "upload": { _, _ in .permanent("local file missing") },
                "comment": { _, _ in .success([:]) }
            ],
            now: { self.t0 }
        )
        await runner.enqueueBatch([
            entry("upX", kind: "upload"),
            entry("cX", kind: "comment", dependsOn: ["upX"]),   // strands (by design)
        ])
        await runner.enqueue(entry("plain", kind: "comment"))    // independent

        let snap = await runner.snapshot()
        XCTAssertEqual(snap.first { $0.id == "plain" }?.status, .completed,
                       "an unrelated failure never blocks a healthy comment")
        XCTAssertEqual(snap.first { $0.id == "cX" }?.status, .failedPermanent,
                       "the starved chain dead-letters visibly (soak stats), not silently")
    }
}

/// Actor mailbox for what the fake comment handler "posted".
private actor PostedCommentsBox {
    private var byId: [String: String?] = [:]
    func record(_ id: String, fileId: String?) { byId[id] = fileId }
    func all() -> [String: String?] { byId }
}
