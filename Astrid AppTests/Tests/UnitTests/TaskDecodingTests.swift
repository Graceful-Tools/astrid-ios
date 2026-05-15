import XCTest
@testable import Astrid_App

/// Decoding contract for the v1 tasks API response.
///
/// Context: 2026-05-14 user report — fresh install on jonparis@gmail.com
/// returned **0 tasks** in the UI for an account with 1188 server-side.
/// Root cause: 2 tasks had `priority: 4`, but the iOS `Task.Priority`
/// enum is rawValue `0...3`. Swift's `Codable` fails the WHOLE array
/// when any single element fails — one bad-priority task silently
/// bricked the entire sync.
///
/// These tests pin two invariants that prevent that class of bug:
///   (a) Unknown priority values decode leniently to `.none`.
///   (b) The wire response decodes element-wise, so a single bad task
///       doesn't drop every other task with it.
final class TaskDecodingTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Priority lenient decode

    /// Unknown priority value (4 — observed in prod for 2 of the user's
    /// 1188 tasks) must NOT throw. Falls back to `.none` so the task
    /// stays usable and the array decode succeeds.
    func test_priority_unknownIntDecodes_toNone() throws {
        let data = "4".data(using: .utf8)!
        let priority = try decoder.decode(Task.Priority.self, from: data)
        XCTAssertEqual(priority, .none)
    }

    /// Negative priorities (defensive — shouldn't occur, but a strict
    /// decode would still brick sync if they ever did).
    func test_priority_negativeIntDecodes_toNone() throws {
        let data = "-1".data(using: .utf8)!
        let priority = try decoder.decode(Task.Priority.self, from: data)
        XCTAssertEqual(priority, .none)
    }

    /// Known values still decode to the right case.
    func test_priority_knownValuesUnaffected() throws {
        for (raw, expected) in [(0, Task.Priority.none),
                                 (1, .low),
                                 (2, .medium),
                                 (3, .high)] {
            let data = String(raw).data(using: .utf8)!
            let priority = try decoder.decode(Task.Priority.self, from: data)
            XCTAssertEqual(priority, expected, "raw \(raw)")
        }
    }

    // MARK: - Task array element-wise resilience

    /// **Regression test for the 0-tasks bug.** An array containing
    /// one task with a wire-shape we can't decode strictly must NOT
    /// drop every OTHER task in the response. The wire envelope
    /// decodes element-wise; bad elements are skipped.
    func test_tasksResponse_oneBadTask_doesNotEatTheArray() throws {
        // Three tasks: two normal, one with priority=4 (the prod case).
        // The strict decoder would fail the entire array on the bad one.
        let json = """
        {
          "tasks": [
            {
              "id": "a", "title": "Alpha", "description": "",
              "isAllDay": false, "priority": 0, "isPrivate": true,
              "completed": false
            },
            {
              "id": "b", "title": "Beta", "description": "",
              "isAllDay": false, "priority": 4, "isPrivate": true,
              "completed": false
            },
            {
              "id": "c", "title": "Gamma", "description": "",
              "isAllDay": false, "priority": 1, "isPrivate": true,
              "completed": false
            }
          ],
          "meta": { "total": 3 }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(TasksResponse.self, from: json)
        let ids = response.tasks.map { $0.id }
        XCTAssertEqual(ids, ["a", "b", "c"],
                       "All three tasks must survive — priority=4 falls back to .none, not a hard fail")

        // The bad-priority task should still be present with priority=.none.
        // (Use the fully-qualified name so `.none` resolves to the
        // Priority case, not Optional.none.)
        let bad = response.tasks.first { $0.id == "b" }
        XCTAssertEqual(bad?.priority, Task.Priority.none)
    }

    /// Even if a task is structurally broken (missing a required field
    /// that has no default), the surrounding tasks survive — the array
    /// decode is element-wise resilient, not all-or-nothing.
    func test_tasksResponse_structurallyBrokenTask_othersStillDecode() throws {
        // Middle task is missing required `id` — strict decoder would
        // throw. The resilient envelope drops it and keeps the rest.
        let json = """
        {
          "tasks": [
            { "id": "a", "title": "Alpha", "description": "",
              "isAllDay": false, "priority": 0, "isPrivate": true,
              "completed": false },
            { "title": "Beta", "description": "",
              "isAllDay": false, "priority": 1, "isPrivate": true,
              "completed": false },
            { "id": "c", "title": "Gamma", "description": "",
              "isAllDay": false, "priority": 2, "isPrivate": true,
              "completed": false }
          ],
          "meta": { "total": 3 }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(TasksResponse.self, from: json)
        let ids = response.tasks.map { $0.id }
        XCTAssertEqual(ids, ["a", "c"], "Structurally broken task is skipped; others kept")
    }
}
