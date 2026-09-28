import AstridCore
import XCTest

/// The client door, driven from Swift: an in-memory cache, no network, no background loops.
final class CoreSessionTests: XCTestCase {
    final class Credentials: CoreCredentialStore, @unchecked Sendable {
        private var values: [String: String] = [:]
        private let lock = NSLock()
        func get(key: String) -> String? { lock.withLock { values[key] } }
        func set(key: String, value: String) -> Bool { lock.withLock { values[key] = value }; return true }
        func delete(key: String) -> Bool { lock.withLock { values[key] = nil }; return true }
    }

    private func session() throws -> CoreSession {
        try CoreSession(cachePath: ":memory:", credentials: Credentials(), background: false)
    }

    private struct Command: Encodable {
        let kind: String
        var name: String?
        var title: String?
        var listIds: [String]?
        var listId: String?
        var limit: Int?
        var offset: Int?
    }

    private struct Created: Decodable { let id: String }
    private struct Rows: Decodable {
        struct Row: Decodable { let id: String; let title: String }
        let total: Int
        let rows: [Row]
    }

    func testACommandRunsAndAnswers() async throws {
        let core = try session()
        let list = try await core.run(Command(kind: "createList", name: "Groceries"), as: Created.self)
        _ = try await core.run(Command(kind: "createTask", title: "Buy milk", listIds: [list.id]), as: Created.self)
        let rows = try await core.run(Command(kind: "rowsForList", listId: list.id), as: Rows.self)
        XCTAssertEqual(rows.total, 1)
        XCTAssertEqual(rows.rows.first?.title, "Buy milk")
    }

    func testAnUnknownCommandIsAFailureNotACrash() async throws {
        let core = try session()
        do {
            try await core.run(Command(kind: "somethingLater"))
            XCTFail("an unknown command must fail")
        } catch let failure as CoreFailure {
            XCTAssertEqual(failure.kind, .badRequest)
        }
    }

    /// The spike's number: one window of a 10,000-task list, asked from Swift. Windows measured
    /// ~30 ms in the core alone (astrid-windows docs/PROGRESS.md); the bridge adds a JSON encode, a
    /// hop onto the core's pool and back, and a decode.
    func testAWindowOfATenThousandTaskListIsQuick() async throws {
        let core = try session()
        let list = try await core.run(Command(kind: "createList", name: "Big"), as: Created.self)
        let seedStart = ContinuousClock.now
        for index in 0..<10_000 {
            _ = try await core.run(
                Command(kind: "createTask", title: "Task \(index)", listIds: [list.id]), as: Created.self)
        }
        print("seeded 10k tasks through the door in \(ContinuousClock.now - seedStart)")

        var times: [Duration] = []
        for offset in [0, 5_000, 0, 5_000, 0] {
            let start = ContinuousClock.now
            let rows = try await core.run(
                Command(kind: "rowsForList", listId: list.id, limit: 50, offset: offset), as: Rows.self)
            times.append(ContinuousClock.now - start)
            XCTAssertEqual(rows.total, 10_000)
            XCTAssertEqual(rows.rows.count, 50)
        }
        print("rowsForList, 50 of 10k, from Swift: \(times)")
        XCTAssertLessThan(times.min()!, .milliseconds(500), "a shape change, not a percentage")
    }
}

final class CoreChangeTests: XCTestCase {
    func testTheCoresWordsReadAsChanges() {
        XCTAssertEqual(CoreChange(json: #"{"change":"task","id":"t1"}"#), .task(id: "t1"))
        XCTAssertEqual(CoreChange(json: #"{"change":"synced","taskIds":[],"listIds":["l1"]}"#),
                       .synced(taskIds: [], listIds: ["l1"]))
        XCTAssertEqual(CoreChange(json: #"{"change":"agentTyping","channelId":"c","active":true}"#),
                       .agentTyping(channelId: "c", active: true))
    }

    func testSomethingNewerIsUnknownNotACrash() {
        guard case .unknown = CoreChange(json: #"{"change":"somethingLater"}"#) else {
            return XCTFail("unknown")
        }
    }
}
