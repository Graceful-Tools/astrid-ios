//  MacUndoMenuRefreshDeferralTests.swift
//  Task 1d995968 — "[mac] SwiftUI: publishing changes from within view updates".
//
//  The monkey run on 2026-08-27 caught one SwiftUI Fault about ten seconds in:
//  "Publishing changes from within view updates is not allowed, this will cause
//  undefined behavior." It leaves no stack in the system log, and it fails no test.
//
//  MacUndoCoordinator is the one place in the Mac target that fires objectWillChange
//  straight out of a synchronous AppKit notification. Two of the five it observes —
//  NSText.didBeginEditingNotification and NSText.didEndEditingNotification — are posted
//  while AppKit is making a text view first responder, and on macOS that happens INSIDE
//  the SwiftUI update that put the TextField on screen. NotificationCenter runs a
//  block-based observer inline when it is already on the observer's queue, so the send
//  landed in the middle of that update — and the Edit menu observes this object, so it
//  is a real publish to a real subscriber mid-update.
//
//  The fix is the one the task describes: get the write out of the view update. The
//  refresh is coalesced onto the next main-queue turn, which also means a burst of
//  editing notifications rebuilds the menu titles once instead of five times.
//
//  Deliberately NOT reverted to a synchronous send if this ever looks unnecessary: the
//  header on MacUndoCoordinator records that turning every checkpoint into a menu
//  rebuild wedged the app at launch, and a synchronous send is the same shape of
//  mistake.

import XCTest
import Combine
@testable import Astrid_Mac

@MainActor
final class MacUndoMenuRefreshDeferralTests: XCTestCase {

    private var bag: Set<AnyCancellable> = []

    override func tearDown() async throws {
        bag.removeAll()
    }

    /// The notifications AppKit posts synchronously while SwiftUI is updating.
    private let editingNotifications: [Notification.Name] = [
        NSText.didBeginEditingNotification,
        NSText.didEndEditingNotification,
        .NSUndoManagerDidUndoChange,
        .NSUndoManagerDidRedoChange,
        .NSUndoManagerDidCloseUndoGroup
    ]

    func testNoNotificationPublishesSynchronously() {
        let coordinator = MacUndoCoordinator()
        var sends = 0
        coordinator.objectWillChange.sink { _ in sends += 1 }.store(in: &bag)

        for name in editingNotifications {
            sends = 0
            NotificationCenter.default.post(name: name, object: NSText())
            XCTAssertEqual(sends, 0, """
                \(name.rawValue) published DURING the post. AppKit posts this while SwiftUI is \
                updating, so the send lands inside the view update — which is the fault.
                """)
        }
    }

    func testTheRefreshStillArrives() async {
        let coordinator = MacUndoCoordinator()
        var sends = 0
        coordinator.objectWillChange.sink { _ in sends += 1 }.store(in: &bag)

        NotificationCenter.default.post(name: NSText.didBeginEditingNotification, object: NSText())
        await nextMainQueueTurn()

        XCTAssertEqual(sends, 1, "deferring must not mean dropping — the Edit menu still has to re-title")
    }

    func testABurstCoalescesIntoOneRefresh() async {
        // Typing posts these constantly. One rebuild per turn is the point of the
        // deferral, not an incidental benefit — the header records that a rebuild per
        // notification is what wedged the app at launch once already.
        let coordinator = MacUndoCoordinator()
        var sends = 0
        coordinator.objectWillChange.sink { _ in sends += 1 }.store(in: &bag)

        for name in editingNotifications {
            NotificationCenter.default.post(name: name, object: NSText())
        }
        await nextMainQueueTurn()

        XCTAssertEqual(sends, 1, "five notifications in one turn must rebuild the menu once")
    }

    /// THE ONE THAT KEEPS THE APP RUNNING. Deferring alone is not enough: a deferred send
    /// starts a fresh update cycle, a menu rebuild closes an undo group, closing a group
    /// posts NSUndoManagerDidCloseUndoGroup, and that schedules another rebuild — forever.
    /// The header on MacUndoCoordinator records that a rebuild-per-notification wedged the
    /// app at launch once already, and deferring on its own hung the Mac test host while
    /// this was being written. Nothing published when nothing changed is what settles it.
    func testAnUnchangedMenuPublishesNothing() async {
        let coordinator = MacUndoCoordinator()
        var sends = 0
        coordinator.objectWillChange.sink { _ in sends += 1 }.store(in: &bag)

        NotificationCenter.default.post(name: NSText.didBeginEditingNotification, object: NSText())
        await nextMainQueueTurn()
        sends = 0

        NotificationCenter.default.post(name: NSText.didEndEditingNotification, object: NSText())
        await nextMainQueueTurn()

        XCTAssertEqual(sends, 0, "the titles did not change, so re-publishing only feeds the loop")
    }

    /// And the other direction: quiet must not mean stuck. A real change still re-titles the
    /// menu, or ⌘Z advertises the wrong action forever — which is worse than the fault.
    func testARealChangeStillPublishes() async {
        let coordinator = MacUndoCoordinator()
        let manager = UndoManager()
        manager.groupsByEvent = false
        coordinator.undoManager = manager

        var sends = 0
        coordinator.objectWillChange.sink { _ in sends += 1 }.store(in: &bag)
        NotificationCenter.default.post(name: NSText.didBeginEditingNotification, object: NSText())
        await nextMainQueueTurn()
        sends = 0
        let before = coordinator.undoTitle

        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { _ in }
        manager.setActionName("Complete Task")
        manager.endUndoGrouping()
        await nextMainQueueTurn()

        XCTAssertNotEqual(coordinator.undoTitle, before, "fixture: the title has to actually move")
        XCTAssertEqual(sends, 1)
    }

    // MARK: - Helpers

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            // Two hops: the first lands behind the coordinator's own async, the second
            // after the send it makes.
            DispatchQueue.main.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}
