import XCTest
@testable import Astrid_App

/// Task c6e87fb8 — the "Recently completed" sort (`sortBy = "completedAt"`).
///
/// Web shipped it; iOS had no `case "completedAt"` in `compareTasksBySort`, so the
/// value fell through `default:` to auto ordering. The field already round-trips
/// through `PUT /api/v1/lists/:id`, which is the quiet part: a list web had already
/// switched to this sort just rendered in auto order on the phone, with nothing to
/// suggest the setting had been dropped.
///
/// Semantics are `astrid-web/lib/task-sort.ts` verbatim — this is a cross-platform
/// contract, and one platform sorting differently is a bug on whichever moved.
final class RecentlyCompletedSortTests: XCTestCase {

    private let sort = "completedAt"
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func task(_ id: String,
                      completed: Bool = false,
                      completedAt: TimeInterval? = nil,
                      updatedAt: TimeInterval? = nil,
                      priority: Task.Priority = .none,
                      due: TimeInterval? = nil) -> Task {
        var t = Task(id: id, title: id, description: "", creatorId: "u1")
        t.completed = completed
        t.completedAt = completedAt.map { base.addingTimeInterval($0) }
        t.updatedAt = updatedAt.map { base.addingTimeInterval($0) }
        t.priority = priority
        t.dueDateTime = due.map { base.addingTimeInterval($0) }
        return t
    }

    private func sorted(_ tasks: [Task]) -> [String] {
        sortTasksForList(tasks, sortBy: sort).map(\.id)
    }

    // MARK: - The sort itself

    func testCompletedTasksLead() {
        // The sort exists to review what got done, so the done half comes first.
        let result = sorted([task("open"), task("done", completed: true, completedAt: 100)])
        XCTAssertEqual(result, ["done", "open"])
    }

    func testMostRecentlyCompletedComesFirst() {
        let result = sorted([
            task("old",    completed: true, completedAt: 100),
            task("newest", completed: true, completedAt: 300),
            task("middle", completed: true, completedAt: 200)
        ])
        XCTAssertEqual(result, ["newest", "middle", "old"])
    }

    func testUpdatedAtStandsInWhenCompletedAtIsAbsent() {
        // `completedAt` is the real stamp and is backdatable by sync; `updatedAt`
        // is the legacy fallback — the same convention as the recently-completed
        // window. A task completed before the column existed still sorts sanely.
        let result = sorted([
            task("legacy", completed: true, updatedAt: 500),
            task("stamped", completed: true, completedAt: 200)
        ])
        XCTAssertEqual(result, ["legacy", "stamped"])
    }

    func testCompletedAtWinsOverUpdatedAtWhenBothArePresent() {
        // A task touched recently but completed long ago belongs down the list.
        let result = sorted([
            task("touched-late", completed: true, completedAt: 100, updatedAt: 900),
            task("done-late",    completed: true, completedAt: 400, updatedAt: 400)
        ])
        XCTAssertEqual(result, ["done-late", "touched-late"])
    }

    func testATaskWithNoStampAtAllSortsLast() {
        let result = sorted([
            task("no-stamp", completed: true),
            task("stamped",  completed: true, completedAt: 100)
        ])
        XCTAssertEqual(result, ["stamped", "no-stamp"])
    }

    // MARK: - The open half

    func testTheIncompleteHalfKeepsAutoOrdering() {
        // It stays a usable to-do list rather than being scrambled: priority
        // first, then due date — exactly what `auto` does.
        let tasks = [
            task("low-priority",  priority: .low,  due: 100),
            task("high-priority", priority: .high, due: 900),
            task("done",          completed: true, completedAt: 50)
        ]
        XCTAssertEqual(sorted(tasks), ["done", "high-priority", "low-priority"])
    }

    func testTheIncompleteHalfBreaksTiesByDueDate() {
        let tasks = [
            task("later",   priority: .medium, due: 900),
            task("sooner",  priority: .medium, due: 100)
        ]
        XCTAssertEqual(sorted(tasks), ["sooner", "later"])
    }

    // MARK: - Contract

    func testTheSortKeyIsRecognisedAndNotSilentlyTreatedAsAuto() {
        // The regression: an unrecognised key falls through `default:` to auto,
        // where the DONE task sorts LAST. If these two agree, the case is missing.
        let tasks = [task("done", completed: true, completedAt: 100), task("open")]

        XCTAssertEqual(sorted(tasks), ["done", "open"])
        XCTAssertEqual(sortTasksForList(tasks, sortBy: "auto").map(\.id), ["open", "done"],
                       "fixture check: auto puts completed last, so the two orders must differ")
    }

    func testCompletedAtIsAKnownSortCase() {
        XCTAssertEqual(TaskSortBy(rawValue: "completedAt"), .completedAt)
    }

    func testTheComparatorIsAntisymmetric() {
        let a = task("a", completed: true, completedAt: 100)
        let b = task("b", completed: true, completedAt: 200)

        XCTAssertEqual(compareTasksBySort(a, b, sortBy: sort), 1)
        XCTAssertEqual(compareTasksBySort(b, a, sortBy: sort), -1)
        XCTAssertEqual(compareTasksBySort(a, a, sortBy: sort), 0)
    }
}

/// The picker half of task c6e87fb8. The comparator knowing the key is useless if
/// nothing offers it — and the sort value is a cross-platform contract, so the tag
/// has to be web's spelling exactly.
final class RecentlyCompletedSortPickerTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testEverySortPickerOffersRecentlyCompleted() throws {
        for path in ["Astrid App/Views/Lists/ListSortFiltersTab.swift",
                     "Astrid App/Views/Lists/ListFiltersView.swift",
                     "Astrid Mac/Views/MacListFilter.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("completedAt"),
                          "\(path) has no \"completedAt\" sort option")
            XCTAssertTrue(text.contains("lists.recently_completed"),
                          "\(path) hardcodes the label instead of using the shared key")
        }
    }

    func testTheLabelIsTranslatedEverywhere() throws {
        // 12 languages, and the key already existed for the recently-completed
        // window — reused rather than duplicated with different words.
        for language in ["en", "de", "es", "fr", "it", "nl", "pt", "ru", "ja", "ko", "zh-Hans", "zh-Hant"] {
            let text = try source("Astrid App/Resources/Localizations/\(language).lproj/Localizable.strings")
            XCTAssertTrue(text.contains("\"lists.recently_completed\""),
                          "\(language) is missing lists.recently_completed")
        }
    }

    func testASavedFilterNamesTheSortInsteadOfShowingTheRawKey() throws {
        let text = try source("Astrid App/Views/Lists/SaveFilterDialog.swift")
        XCTAssertTrue(text.contains("case \"completedAt\":"),
                      "a saved filter would render the raw \"completedAt\"")
    }
}
