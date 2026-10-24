//  MacSurfaceBehaviourTests.swift
//  The Mac-only behaviour that had no test (AITD-540): the menu-bar extra, the command palette,
//  the quick changer, the sort menu, the global hot key, the blockers row, wake recovery, the
//  account screen and two small helpers. Each view's rule is pulled out where it was inlined, and
//  tested through the production path.

#if os(macOS)
import AppKit
import XCTest
@testable import Astrid_Mac

// MARK: - Menu bar and palette

final class MacGlanceTasksTests: XCTestCase {
    private func task(_ id: String, due: TimeInterval? = nil, priority: Task.Priority = .none,
                      completed: Bool = false) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.dueDateTime = due.map { Date(timeIntervalSince1970: $0) }
        t.priority = priority
        return t
    }

    private let lists = [TaskList(id: "home", name: "Home"), TaskList(id: "work", name: "Work")]

    /// The bug this found: both surfaces flat-mapped over the lists, so a task filed in two lists
    /// took two of the menu bar's eight slots and showed twice in the palette.
    func testATaskInTwoListsIsOneTask() {
        let shared = task("shared")
        let byList = ["home": [shared, task("a")], "work": [shared]]
        XCTAssertEqual(MacGlanceTasks.all(lists: lists, tasksForList: { byList[$0] ?? [] }).map(\.id), ["shared", "a"])
        XCTAssertEqual(MacGlanceTasks.open(lists: lists, tasksForList: { byList[$0] ?? [] }).filter { $0.id == "shared" }.count, 1)
    }

    func testOpenTasksAreSoonestFirstThenHighestPriorityAndCapped() {
        let tasks = [task("later", due: 2_000), task("done", due: 1, completed: true), task("undated-high", priority: .high),
                     task("soon", due: 1_000), task("undated-low", priority: .low)]
        let open = MacGlanceTasks.open(lists: [lists[0]], tasksForList: { _ in tasks }, limit: 3)
        XCTAssertEqual(open.map(\.id), ["soon", "later", "undated-high"],
                       "completed tasks never show; dated before undated; priority breaks the tie; at most `limit`")
    }

    func testThePaletteRunsTheSelectionOrElseTheFirstRow() {
        XCTAssertEqual(CommandPalettePick.rowToRun(selection: "task:b", rowIds: ["cmd:x", "task:b"]), "task:b")
        XCTAssertEqual(CommandPalettePick.rowToRun(selection: "task:gone", rowIds: ["cmd:x", "task:b"]), "cmd:x",
                       "a selection the query filtered away falls back to the first row")
        XCTAssertEqual(CommandPalettePick.rowToRun(selection: nil, rowIds: ["cmd:x"]), "cmd:x")
        XCTAssertNil(CommandPalettePick.rowToRun(selection: nil, rowIds: []))
    }
}

// MARK: - Quick changer

@MainActor
private final class RecordingWriter: MacTaskWriting {
    var writes: [String] = []
    func writePriority(_ priority: Int, of task: Task) async throws { writes.append("priority \(priority) \(task.id)") }
    func writeAssignee(_ assigneeId: String, of task: Task) async throws { writes.append("assignee '\(assigneeId)' \(task.id)") }
    func writeCompletion(_ completed: Bool, of task: Task) async throws { writes.append("complete \(completed) \(task.id)") }
}

@MainActor
final class MacQuickChangerWriteTests: XCTestCase {
    func testEachControlWritesThroughItsOwnCall() async throws {
        let writer = RecordingWriter()
        let open = Task(id: "t", title: "t", completed: false)
        try await MacQuickChangerWrite.priority(.high).apply(to: writer, task: open)
        try await MacQuickChangerWrite.assignee("u1").apply(to: writer, task: open)
        try await MacQuickChangerWrite.assignee(nil).apply(to: writer, task: open)
        try await MacQuickChangerWrite.toggleCompletion.apply(to: writer, task: open)
        try await MacQuickChangerWrite.toggleCompletion.apply(to: writer, task: Task(id: "d", title: "d", completed: true))
        XCTAssertEqual(writer.writes, [
            "priority \(Task.Priority.high.rawValue) t",
            "assignee 'u1' t",
            "assignee '' t",            // clearing sends "", which the service reads as unassigned
            "complete true t",          // through completeTask: the path that rolls a repeat forward
            "complete false d",
        ])
    }
}

// MARK: - Sort menu

final class MacSortMenuPayloadTests: XCTestCase {
    /// Every option writes `sortBy` and only `sortBy` — what the settings sheet sends for the same
    /// change through `ListSettingsPayload`, so the two ways to sort a list cannot disagree.
    func testEveryOptionWritesOnlySortByAsTheSettingsSheetDoes() {
        XCTAssertFalse(MacListFilter.sort.isEmpty)
        for option in MacListFilter.sort {
            let menu = MacSortMenu.listUpdates(sortBy: option.value)
            XCTAssertEqual(Array(menu.keys), ["sortBy"], option.value)
            XCTAssertEqual(menu["sortBy"] as? String, option.value)

            var original = TaskList(id: "l", name: "L")
            original.sortBy = option.value == "auto" ? "manual" : "auto"
            var updated = original
            updated.sortBy = option.value
            let sheet = ListSettingsPayload.updates(original: original, updated: updated)
            XCTAssertEqual(sheet["sortBy"] as? String, option.value, "\(option.value): the sheet writes the same value")
        }
    }
}

// MARK: - Global hot key

private final class FakeRegistrar: HotKeyRegistrar {
    var refuse = false
    var registered: [(keyCode: UInt32, modifiers: UInt32, id: UInt32)] = []
    var released: [UInt32] = []
    var actions: [UInt32: () -> Void] = [:]

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, onPress: @escaping () -> Void) -> AnyObject? {
        guard !refuse else { return nil }
        registered.append((keyCode, modifiers, id))
        actions[id] = onPress
        return NSObject()
    }

    func unregister(_ handle: AnyObject, id: UInt32) { released.append(id) }
}

@MainActor
final class GlobalHotKeyTests: XCTestCase {
    func testRegistersTheKeyAndReleasesItWhenGone() throws {
        let registrar = FakeRegistrar()
        var pressed = 0
        var hotKey: GlobalHotKey? = GlobalHotKey(keyCode: GlobalHotKey.optionSpace.keyCode,
                                                 modifiers: GlobalHotKey.optionSpace.modifiers,
                                                 registrar: registrar) { pressed += 1 }
        XCTAssertNotNil(hotKey)
        let registration = try XCTUnwrap(registrar.registered.first)
        XCTAssertEqual(registrar.registered.count, 1)
        XCTAssertEqual(registration.keyCode, GlobalHotKey.optionSpace.keyCode)
        XCTAssertEqual(registration.modifiers, GlobalHotKey.optionSpace.modifiers)
        registrar.actions[registration.id]?()
        XCTAssertEqual(pressed, 1, "a press reaches the action")

        hotKey = nil
        XCTAssertEqual(registrar.released, [registration.id], "the key is released with its owner")
    }

    func testARefusedKeyLeavesNothingBehind() {
        let registrar = FakeRegistrar()
        registrar.refuse = true
        XCTAssertNil(GlobalHotKey(keyCode: 1, modifiers: 0, registrar: registrar) {})
        XCTAssertTrue(registrar.released.isEmpty, "nothing was registered, so nothing is released")
    }

    func testTheQuickEntryControllerRegistersOnce() {
        let registrar = FakeRegistrar()
        let controller = QuickEntryHotKeyController { action in
            GlobalHotKey(keyCode: 1, modifiers: 0, registrar: registrar, action: action)
        }
        controller.registerIfNeeded()
        controller.registerIfNeeded()
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(registrar.registered.count, 1, "asking again while registered registers nothing")
    }

    func testAFailedRegistrationIsTriedAgainNextTime() {
        let registrar = FakeRegistrar()
        registrar.refuse = true
        let controller = QuickEntryHotKeyController { action in
            GlobalHotKey(keyCode: 1, modifiers: 0, registrar: registrar, action: action)
        }
        controller.registerIfNeeded()
        XCTAssertFalse(controller.isRegistered)
        registrar.refuse = false
        controller.registerIfNeeded()
        XCTAssertTrue(controller.isRegistered)
    }
}

// MARK: - Blockers row

final class MacTaskBlockersTests: XCTestCase {
    func testTheSearchLeavesOutBothDirectionsAndWhatWasJustAdded() {
        let blockedBy = [TaskBlocker(id: "b1", title: "B1", identifier: nil, completed: false, hidden: nil)]
        let base = MacTaskBlockers.excludedIds(blockedBy: blockedBy, dependentIds: ["d1"])
        XCTAssertEqual(base, ["b1", "d1"], "what blocks it and what it blocks — either would make a cycle")
        XCTAssertEqual(MacTaskBlockers.excludedIds(base: base, added: ["n1"]), ["b1", "d1", "n1"])
    }
}

// MARK: - Wake recovery

@MainActor
final class MacWakeRecoveryLifecycleTests: XCTestCase {
    override func tearDown() async throws {
        MacWakeRecovery.stop()
        try await super.tearDown()
    }

    func testOneWakeReconnectsOnceHoweverOftenItWasStarted() async {
        let center = NotificationCenter()
        var reconnects = 0
        let reconnected = expectation(description: "reconnect")
        MacWakeRecovery.start(center: center) { reconnects += 1; reconnected.fulfill() }
        MacWakeRecovery.start(center: center) { reconnects += 100 }   // already watching: ignored

        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fulfillment(of: [reconnected], timeout: 2)
        XCTAssertEqual(reconnects, 1)
    }

    func testStoppingStopsTheReconnect() async {
        let center = NotificationCenter()
        var reconnects = 0
        MacWakeRecovery.start(center: center) { reconnects += 1 }
        MacWakeRecovery.stop()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await _Concurrency.Task.yield()
        XCTAssertEqual(reconnects, 0)
    }
}

// MARK: - Account screen

final class MacAccountRulesTests: XCTestCase {
    func testARenameIsSentOnlyWhenSomethingChanged() {
        XCTAssertEqual(MacAccountRules.renamed(from: "Jon", to: "  Jonathan "), "Jonathan")
        XCTAssertNil(MacAccountRules.renamed(from: "Jon", to: "Jon"), "unchanged sends nothing")
        XCTAssertNil(MacAccountRules.renamed(from: "Jon", to: "   "), "a blank name is never saved")
        XCTAssertEqual(MacAccountRules.renamed(from: nil, to: "Jon"), "Jon")
    }

    func testDeleteAsksFirst() {
        XCTAssertFalse(MacAccountRules.mayDelete(confirmation: "", working: false))
        XCTAssertFalse(MacAccountRules.mayDelete(confirmation: "delete", working: false), "exactly DELETE")
        XCTAssertTrue(MacAccountRules.mayDelete(confirmation: "DELETE", working: false))
        XCTAssertFalse(MacAccountRules.mayDelete(confirmation: "DELETE", working: true), "not twice")
    }
}

// MARK: - Small helpers

final class MacDetailRowHelpersTests: XCTestCase {
    func testEveryProjectFieldKindHasItsOwnResolvableIcon() {
        let kinds: [ProjectFieldRow.Kind?] = [.number, .date, .singleSelect, .iteration, .text, nil]
        let icons = kinds.map(MacTaskProjectFieldsRows.icon(for:))
        for icon in icons {
            XCTAssertNotNil(NSImage(systemSymbolName: icon, accessibilityDescription: nil), icon)
        }
        XCTAssertEqual(Set(icons.dropLast(2)).count, 4, "each typed field draws its own glyph")
        XCTAssertEqual(icons[4], icons[5], "text and an unknown kind share the plain-text glyph")
    }

    func testAPlaceholderSubtaskTakesItsListsDefaultPriority() {
        var parent = Task(id: "p", title: "p", completed: false)
        parent.priority = .low
        parent.listIds = ["l1", "l2"]
        var withDefault = TaskList(id: "l2", name: "Two")
        withDefault.defaultPriority = Task.Priority.high.rawValue
        XCTAssertEqual(MacSubtaskRow.placeholderPriority(for: parent, lists: ["l1": TaskList(id: "l1", name: "One"), "l2": withDefault]),
                       .high, "the first list that has a default decides")
        XCTAssertEqual(MacSubtaskRow.placeholderPriority(for: parent, lists: [:]), .low,
                       "with no list default, the parent's priority")
        var nonsense = TaskList(id: "l1", name: "One")
        nonsense.defaultPriority = 42
        XCTAssertEqual(MacSubtaskRow.placeholderPriority(for: parent, lists: ["l1": nonsense]), .low,
                       "an unreadable default falls back rather than inventing a priority")
    }
}
#endif
