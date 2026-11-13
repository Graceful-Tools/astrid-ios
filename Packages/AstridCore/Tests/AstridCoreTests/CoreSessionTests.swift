@testable import AstridCore
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

    /// Named because the core has no default server (AITD-651); never reached — no background loops.
    static let server = "https://astrid.cc"

    private func session() throws -> CoreSession {
        try CoreSession(cachePath: ":memory:", baseURL: Self.server, credentials: Credentials(), background: false)
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

    /// AITD-643: the binding is astrid-core's shared `astrid-uniffi`, and its version names the core
    /// revision it was built from (`0.1.0 (core 9128b8a9d3da)`), so a crash report says which core.
    func testTheCoreVersionNamesItsRevision_AITD643() {
        let version = CoreSession.coreVersion
        XCTAssertTrue(version.contains(" (core "), version)
        XCTAssertFalse(version.contains("(core unknown)"), version)
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
                       .agentTyping(channelId: "c", taskId: nil, agentName: nil, active: true))
        XCTAssertEqual(
            CoreChange(json: #"{"change":"agentTyping","channelId":null,"taskId":"t","agentName":"Claude","active":false}"#),
            .agentTyping(channelId: nil, taskId: "t", agentName: "Claude", active: false))
        XCTAssertEqual(CoreChange(json: #"{"change":"stream","live":true}"#), .stream(live: true))
    }

    /// AITD-454: a delivery names what it touched and carries the journal's counts.
    func testADeliveryReadsWithWhatItTouched_AITD454() {
        let json = #"{"change":"delivered","taskIds":["temp_1","t1"],"listIds":[],"commentTaskIds":["t9"],"channelIds":[],"undescribed":false,"pending":2,"running":1,"failed":0}"#
        XCTAssertEqual(CoreChange(json: json), .delivered(CoreDelivery(
            taskIds: ["temp_1", "t1"], listIds: [], commentTaskIds: ["t9"], channelIds: [],
            undescribed: false, pending: 2, running: 1, failed: 0)))
        // Missing fields are not a reason to drop it: what it cannot say, it says it cannot.
        XCTAssertEqual(CoreChange(json: #"{"change":"delivered"}"#), .delivered(CoreDelivery(
            taskIds: [], listIds: [], commentTaskIds: [], channelIds: [],
            undescribed: true, pending: 0, running: 0, failed: 0)))
    }

    func testSomethingNewerIsUnknownNotACrash() {
        guard case .unknown = CoreChange(json: #"{"change":"somethingLater"}"#) else {
            return XCTFail("unknown")
        }
    }

    /// AITD-616: a white-label build names its scheme and hand-off client; Astrid sends neither,
    /// and absence is the core's default — never an empty string.
    func testTheStartConfigCarriesTheBrandsSchemeOnlyWhenGiven_AITD616() throws {
        func keys(_ json: String) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        }
        let partner = try keys(CoreSession.configJSON(cachePath: ":memory:", baseURL: CoreSessionTests.server, platform: .ios,
                                                      urlScheme: "acmetasks", handoffClientId: "acme-ios"))
        XCTAssertEqual(partner["urlScheme"] as? String, "acmetasks")
        XCTAssertEqual(partner["handoffClientId"] as? String, "acme-ios")
        XCTAssertEqual(partner["platform"] as? String, "ios-app")

        let plain = try keys(CoreSession.configJSON(cachePath: ":memory:", baseURL: CoreSessionTests.server, platform: nil,
                                                    urlScheme: nil, handoffClientId: nil))
        XCTAssertNil(plain["urlScheme"])
        XCTAssertNil(plain["handoffClientId"])

        // And the core accepts it.
        _ = try CoreSession(cachePath: ":memory:", baseURL: CoreSessionTests.server, urlScheme: "acmetasks", handoffClientId: "acme-ios",
                            credentials: CoreSessionTests.Credentials(), background: false)
    }

    /// AITD-651 (astrid-web AWTD-1627): the server is the shell's to name, always. A core built
    /// with `require-base-url` has no default and refuses a start config without one, so a
    /// white-label binary can never reach astrid.cc by omission. `baseURL` is a required `String`
    /// (the `core-base-url-required` source contract keeps it so) and it is always on the wire.
    func testTheStartConfigAlwaysNamesTheServer_AITD651() throws {
        let json = try CoreSession.configJSON(cachePath: ":memory:", baseURL: "https://tasks.example.com",
                                              platform: nil, urlScheme: nil, handoffClientId: nil)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(keys["baseUrl"] as? String, "https://tasks.example.com")
    }
}
