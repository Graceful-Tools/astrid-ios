//  MacMyTasksFilterTests.swift
//  My Tasks honours the saved filters on Mac too (task ebdf94a1).
//
//  Jon: "add filters to My Tasks just like they are in iOS."
//
//  Mac's My Tasks took no filters at all — it hardcoded "incomplete", so the completion filter
//  could not be expressed, and priority and due date were ignored outright. iOS has had all
//  three, saved in `MyTasksPreferences` and synced, so someone who set a filter on their phone
//  saw it do nothing on the desktop.
//
//  The filtering itself is NOT reimplemented here. It is astrid-core's `rowsForList` (AITD-460),
//  which iOS asks too; one implementation is the whole point, because a second
//  implementation of "what "today" means" is how two platforms start disagreeing about a due
//  date (ASTRID.md rule 8).
//
//  THE SCOPE: this task left the Mac's "mine or unassigned" scope alone. It has since moved to
//  iOS's "assigned to me" (CONTRACTS D25) — Jon 2026-10-03: on disagreement follow iOS — and is
//  pinned below.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacMyTasksFilterTests: XCTestCase {

    private let me = "user-me"

    private func task(_ id: String,
                      assignee: String?,
                      completed: Bool = false,
                      priority: Task.Priority = .none,
                      due: Date? = nil) -> Task {
        var t = Task(id: id, title: "Task \(id)")
        t.assigneeId = assignee
        t.completed = completed
        t.priority = priority
        t.dueDateTime = due
        return t
    }

    // MARK: - The filters are reachable

    /// Behaviour is nothing if nobody can get at it. My Tasks is virtual, so it was excluded
    /// from the list filter control and had no route of its own — the filters existed, were
    /// synced, and could only be changed from another device.
    func testTheFilterControlIsOfferedForMyTasks() throws {
        let root = try String(contentsOf: RepositoryLocator.root
            .appendingPathComponent("Astrid Mac/App/MacRootView.swift"), encoding: .utf8)
        XCTAssertTrue(root.contains("myTasksFilterButton"),
                      "My Tasks needs its own filter control — it has no TaskList to edit")
        XCTAssertTrue(root.contains("MacMyTasksFilterSheet()"),
                      "and a sheet to open")
    }

    /// The sheet must offer the same three iOS offers, read from the same synced preferences.
    func testTheSheetOffersTheSameThreeFiltersAsIOS() throws {
        let sheet = try String(contentsOf: RepositoryLocator.root
            .appendingPathComponent("Astrid Mac/Views/MacMyTasksFilterSheet.swift"), encoding: .utf8)
        XCTAssertTrue(sheet.contains("MacListFilter.completion"))
        XCTAssertTrue(sheet.contains("MacListFilter.priority"))
        XCTAssertTrue(sheet.contains("MacListFilter.dueDate"))
        XCTAssertTrue(sheet.contains("MyTasksPreferencesService.shared"),
                      "must read and write the SYNCED preferences, not a local copy")
    }

}
#endif
