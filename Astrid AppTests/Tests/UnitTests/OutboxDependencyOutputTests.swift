import XCTest
@testable import Astrid_App

/// A completed Outbox entry can produce an output (e.g. an attachment upload
/// yields the real fileId), and its dependents must receive that output so they
/// can fill it into their own request. This is what makes "create the comment
/// with the file that was just uploaded" work without temp-id plumbing.
final class OutboxDependencyOutputTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-dep-\(UUID().uuidString).json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tempURL) }

    private func entry(_ id: String, kind: String, dependsOn: [String] = []) -> OutboxEntry {
        OutboxEntry(
            id: id, kind: kind, payload: Data(), clientRequestId: "crid-\(id)",
            dependsOn: dependsOn, status: .pending, attempts: 0,
            nextAttemptAt: fixedNow, lastError: nil, createdAt: fixedNow, updatedAt: fixedNow
        )
    }

    func testDependentReceivesDependencyOutput() async {
        // "upload" produces fileId; "comment" depends on it and reads it.
        let captured = CapturedFileId()
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: tempURL),
            handlers: [
                "upload": { _, _ in .success(["fileId": "real-file-123"]) },
                "comment": { _, context in
                    await captured.set(context.value("fileId"))
                    return .success([:])
                }
            ],
            now: { self.fixedNow }
        )

        await runner.enqueue(entry("u", kind: "upload"))
        await runner.enqueue(entry("c", kind: "comment", dependsOn: ["u"]))

        let seen = await captured.value
        XCTAssertEqual(seen, "real-file-123",
                       "the comment handler must see the fileId the upload produced")

        let snap = await runner.snapshot()
        XCTAssertEqual(snap.first { $0.id == "u" }?.result?["fileId"], "real-file-123",
                       "the producing entry persists its output")
    }

    private actor CapturedFileId {
        private(set) var value: String?
        func set(_ v: String?) { value = v }
    }
}
