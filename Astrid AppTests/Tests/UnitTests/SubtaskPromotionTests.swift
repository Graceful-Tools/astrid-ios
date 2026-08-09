//  SubtaskPromotionTests.swift
//  Task 2ed0d0de — dragging a subtask out to top level (iOS/Mac), the twin of web b00a1f94.
//
//  These mirror astrid-web's tests/lib/subtask-promotion.test.ts. The web module is the
//  canonical spec; if the two disagree, one platform lets you promote a task the other
//  refuses, and that is a bug rather than a platform difference.

import XCTest
@testable import Astrid_App

final class SubtaskPromotionTests: XCTestCase {

    private struct Row: PromotableTask {
        let id: String
        let parentTaskId: String?
    }

    // MARK: canPromoteToTopLevel

    func testATaskWithAParentCanBePromoted() {
        XCTAssertTrue(SubtaskPromotion.canPromoteToTopLevel(Row(id: "t1", parentTaskId: "p1")))
    }

    func testATopLevelTaskHasNothingToMoveOutOf() {
        XCTAssertFalse(SubtaskPromotion.canPromoteToTopLevel(Row(id: "t1", parentTaskId: nil)))
    }

    /// Web's check is truthiness, so an empty string is NOT a parent. Swift's `!= nil` would
    /// disagree and offer the target for a task with nothing above it.
    func testAnEmptyParentIdIsNotAParent() {
        XCTAssertFalse(SubtaskPromotion.canPromoteToTopLevel(Row(id: "t1", parentTaskId: "")))
    }

    func testNoTaskCannotBePromoted() {
        XCTAssertFalse(SubtaskPromotion.canPromoteToTopLevel(nil))
    }

    // MARK: shouldShowPromoteTarget

    /// The target appears only while a subtask is in flight — a permanent unnest strip would be
    /// noise, since most tasks are not subtasks and most drags are reorders.
    func testTargetIsShownOnlyWhileASubtaskIsDragged() {
        XCTAssertTrue(SubtaskPromotion.shouldShowPromoteTarget(draggedTask: Row(id: "t1", parentTaskId: "p1")))
        XCTAssertFalse(SubtaskPromotion.shouldShowPromoteTarget(draggedTask: Row(id: "t1", parentTaskId: nil)))
        XCTAssertFalse(SubtaskPromotion.shouldShowPromoteTarget(draggedTask: nil))
    }

    // MARK: resolvePromotion

    func testPromotionClearsTheParent() {
        let result = SubtaskPromotion.resolvePromotion(Row(id: "t1", parentTaskId: "p1"))
        XCTAssertEqual(result?.taskId, "t1")
        XCTAssertNil(result?.parentTaskId, "The whole point of the operation is to clear the parent")
    }

    /// A drop on the target for a non-promotable task must be a no-op, not a write that clears
    /// an already-null parent.
    func testDroppingANonSubtaskWritesNothing() {
        XCTAssertNil(SubtaskPromotion.resolvePromotion(Row(id: "t1", parentTaskId: nil)))
        XCTAssertNil(SubtaskPromotion.resolvePromotion(Row(id: "t1", parentTaskId: "")))
        XCTAssertNil(SubtaskPromotion.resolvePromotion(nil))
    }

    /// Promotion cuts ONLY the link to the parent. The task's own children travel with it, still
    /// nested under it — pulling grandchildren up too is a different product decision.
    func testPromotionSaysNothingAboutTheTasksOwnChildren() {
        let result = SubtaskPromotion.resolvePromotion(Row(id: "parent-of-others", parentTaskId: "g1"))
        XCTAssertEqual(result?.taskId, "parent-of-others")
        XCTAssertNil(result?.parentTaskId)
    }

    // MARK: drop target identity

    /// Shared by the view that renders the target and the handler that receives the drop, so the
    /// two cannot drift apart.
    func testDropTargetIdMatchesWeb() {
        XCTAssertEqual(SubtaskPromotion.dropTargetId, "promote-to-top-level")
    }

    // MARK: the real model conforms

    func testTaskItselfIsPromotable() {
        var task = Task(id: "t1", title: "child")
        task.parentTaskId = "p1"
        XCTAssertTrue(SubtaskPromotion.canPromoteToTopLevel(task))
        task.parentTaskId = nil
        XCTAssertFalse(SubtaskPromotion.canPromoteToTopLevel(task))
    }
}
