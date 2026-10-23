import XCTest
@testable import Astrid_App

/// Unit tests for TaskList model and related types
final class TaskListModelTests: XCTestCase {

    // MARK: - Display Color Tests

    func testDisplayColorWithColor() {
        let list = TestHelpers.createTestList(color: "#ff5733")
        XCTAssertEqual(list.displayColor, "#ff5733")
    }

    func testDisplayColorWithNilColor() {
        let list = TestHelpers.createTestList(color: nil)
        XCTAssertEqual(list.displayColor, "#3b82f6")  // Default blue
    }

    // MARK: - Equatable Tests

    @MainActor func testListEquality() {
        let list1 = TestHelpers.createTestList(id: "same-id", name: "List")
        let list2 = TestHelpers.createTestList(id: "same-id", name: "List")

        XCTAssertEqual(list1, list2)
    }

    @MainActor func testListInequality() {
        let list1 = TestHelpers.createTestList(id: "list-1", name: "List One")
        let list2 = TestHelpers.createTestList(id: "list-2", name: "List Two")

        XCTAssertNotEqual(list1, list2)
    }

    // MARK: - Hashable Tests

    @MainActor func testListHashable() {
        let list = TestHelpers.createTestList(id: "hash-list")

        var listSet = Set<TaskList>()
        listSet.insert(list)

        XCTAssertTrue(listSet.contains(list))
    }

    // MARK: - Board fields (added 2026-05-12)

    /// Status lists return all seven board fields under `/api/v1/lists/*`.
    /// This pins the iOS-side decoder against that contract.
    func testDecode_statusListIncludesAllBoardFields() throws {
        let json = """
        {
          "id": "l-ready",
          "name": "Ready",
          "projectId": "p1",
          "listType": "status",
          "statusRole": "ready",
          "statusOrder": 0,
          "statusDescription": "Time to get to work!",
          "statusCompleted": false,
          "recentlyCompletedWindow": null,
          "privacy": "SHARED",
          "ownerId": "u1"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let list = try decoder.decode(TaskList.self, from: json)
        XCTAssertEqual(list.projectId, "p1")
        XCTAssertEqual(list.listType, "status")
        XCTAssertEqual(list.statusRole, "ready")
        XCTAssertEqual(list.statusOrder, 0)
        XCTAssertEqual(list.statusDescription, "Time to get to work!")
        XCTAssertEqual(list.statusCompleted, false)
        XCTAssertNil(list.recentlyCompletedWindow)
    }

    /// Legacy lists with no project attached return null/defaults — make
    /// sure the decoder treats those as absent without crashing.
    func testDecode_legacyListHasNilBoardFields() throws {
        let json = """
        {
          "id": "legacy",
          "name": "Legacy List",
          "privacy": "PRIVATE",
          "ownerId": "u1",
          "projectId": null,
          "listType": "regular",
          "statusRole": null,
          "statusOrder": null,
          "statusDescription": null,
          "statusCompleted": false,
          "recentlyCompletedWindow": null
        }
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode(TaskList.self, from: json)
        XCTAssertNil(list.projectId)
        XCTAssertEqual(list.listType, "regular")
        XCTAssertNil(list.statusRole)
        XCTAssertNil(list.statusOrder)
        XCTAssertNil(list.statusDescription)
        XCTAssertEqual(list.statusCompleted, false)
        XCTAssertNil(list.recentlyCompletedWindow)
    }

    /// AITD-376 / AWTD-853: web is deprecating the four vestigial
    /// `TaskList.status*` columns off the v1 contract, so a list response will
    /// stop carrying the keys AT ALL — not send them as null.
    ///
    /// That is a different decode path from `testDecode_legacyListHasNilBoardFields`
    /// above, which pins explicit nulls. `decodeIfPresent` tolerates both, but
    /// nothing tested the absent case, and the answer this repo gave web ("drop
    /// them, no deprecation window needed, no minimum app version") is only true
    /// while it stays that way. A non-optional or plain `decode(_:forKey:)` on any
    /// of the four would break every list response the day web stops emitting them.
    ///
    /// `statusRole` here is the LIST's, not `Task.statusRole` — that one is the
    /// live board column and is untouched by the deprecation.
    func testDecode_boardFieldsAbsentEntirely_AITD376() throws {
        let json = """
        {
          "id": "post-deprecation",
          "name": "Work",
          "privacy": "SHARED",
          "ownerId": "u1",
          "projectId": "p1",
          "listType": "regular"
        }
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode(TaskList.self, from: json)

        XCTAssertNil(list.statusRole)
        XCTAssertNil(list.statusOrder)
        XCTAssertNil(list.statusDescription)
        XCTAssertNil(list.statusCompleted)

        // The fields the same response still carries must survive the omission.
        XCTAssertEqual(list.id, "post-deprecation")
        XCTAssertEqual(list.projectId, "p1")
        XCTAssertEqual(list.listType, "regular")
    }

    /// `recentlyCompletedWindow` is a discriminated union; iOS must decode
    /// every shape the web emits. Spot-check each kind.
    func testDecode_recentlyCompletedWindow_eachKind() throws {
        struct Wrap: Codable { var window: RecentlyCompletedWindow? }
        let cases: [(String, RecentlyCompletedWindow)] = [
            ("{\"kind\":\"duration\",\"amount\":7,\"unit\":\"day\"}",
             .duration(amount: 7, unit: .day)),
            ("{\"kind\":\"since-weekday\",\"weekday\":1}",
             .sinceWeekday(weekday: 1)),
            ("{\"kind\":\"since-day-of-month\",\"day\":15}",
             .sinceDayOfMonth(day: 15)),
            ("{\"kind\":\"since-date\",\"date\":\"2026-04-01\"}",
             .sinceDate(date: "2026-04-01")),
        ]
        for (windowJson, expected) in cases {
            let json = "{\"window\":\(windowJson)}".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(Wrap.self, from: json)
            XCTAssertEqual(decoded.window, expected)
        }
    }

    /// A TaskList carrying a recentlyCompletedWindow encodes it back as
    /// the same shape iOS receives — important for PUT round-trips.
    func testEncode_taskListWithWindow_roundTrips() throws {
        var list = TestHelpers.createTestList(id: "l-1", name: "List")
        list.projectId = "p-1"
        list.listType = "status"
        list.recentlyCompletedWindow = .duration(amount: 7, unit: .day)

        let data = try JSONEncoder().encode(list)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"projectId\":\"p-1\""))
        XCTAssertTrue(json.contains("\"listType\":\"status\""))
        XCTAssertTrue(json.contains("\"recentlyCompletedWindow\""))

        let decoded = try JSONDecoder().decode(TaskList.self, from: data)
        XCTAssertEqual(decoded.projectId, "p-1")
        XCTAssertEqual(decoded.recentlyCompletedWindow, .duration(amount: 7, unit: .day))
    }

    // MARK: - aiAgentsEnabled wire shapes

    /// Regression for the 2026-08-29 Mac log
    /// `typeMismatch … Path: lists[10].aiAgentsEnabled … Expected to decode Array<Any> but
    /// found a dictionary instead` — one list whose agent config had been saved on the web in the
    /// server's stored object form `{ enabledTypes, defaultAgentId }` failed the decode of the
    /// WHOLE `/api/v1/lists` response, and every list in the account disappeared ("offline mode,
    /// 0 lists"). The server now emits the array again plus a sibling `aiAgentConfig`, but the
    /// client must never let one field on one list zero the cache: an array, a dictionary, and
    /// null must all decode, and the other lists must survive whatever the eleventh one holds.
    func testDecode_aiAgentsEnabled_objectForm_doesNotZeroTheList() throws {
        let json = """
        {"lists":[
          {"id":"l-object","name":"Web-configured","createdAt":"2026-08-29T10:00:00.000Z",
           "aiAgentsEnabled":{"enabledTypes":["claude","coding"],"defaultAgentId":"agent-1"}},
          {"id":"l-array","name":"Legacy","aiAgentsEnabled":["claude"],
           "aiAgentConfig":{"enabledTypes":["claude"],"defaultAgentId":null}},
          {"id":"l-null","name":"Untouched","aiAgentsEnabled":null}
        ]}
        """
        let decoder = TaskListModelTests.apiDecoder()

        let response = try decoder.decode(ListsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.lists.map(\.id), ["l-object", "l-array", "l-null"])

        let object = response.lists[0]
        XCTAssertEqual(object.aiAgentsEnabled, ["claude", "coding"])
        XCTAssertEqual(object.aiAgentConfig?.enabledTypes, ["claude", "coding"],
                       "a dictionary carries the full config — keep it, it's what the web reads")
        XCTAssertEqual(object.aiAgentConfig?.defaultAgentId, "agent-1")

        let array = response.lists[1]
        XCTAssertEqual(array.aiAgentsEnabled, ["claude"])
        XCTAssertEqual(array.aiAgentConfig?.enabledTypes, ["claude"])
        XCTAssertNil(array.aiAgentConfig?.defaultAgentId)

        let untouched = response.lists[2]
        XCTAssertNil(untouched.aiAgentsEnabled)
        XCTAssertNil(untouched.aiAgentConfig, "absent on the wire stays absent — no invented config")
    }

    /// PUT bodies keep sending the array the server has always accepted.
    func testEncode_aiAgentsEnabled_staysAnArray() throws {
        var list = TestHelpers.createTestList(id: "l-1", name: "List")
        list.aiAgentsEnabled = ["claude"]

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(list), encoding: .utf8))

        XCTAssertTrue(json.contains("\"aiAgentsEnabled\":[\"claude\"]"), json)
    }

    /// Mirrors `AstridAPIClient`'s decoder (which is private): ISO8601 with or without
    /// fractional seconds. The field under test doesn't depend on it, but the payload above is
    /// what the real endpoint returns and should decode through the same configuration.
    private static func apiDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: dateString) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return decoder
    }
}
