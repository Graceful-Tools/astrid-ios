//  DragNestingTests.swift
//  What a task drag MEANS, shared by Mac and iOS.
//
//  Three zones, three meanings:
//    · over a row              → nest under it
//    · on the line BETWEEN rows → become top level, positioned there
//    · dragged far enough left  → outdent one level
//
//  The rules live away from the drag handlers because they are answerable without a view,
//  and because Mac and iOS must not disagree about them. This is the same reason
//  SubtaskPromotion exists, and these build on it.

import XCTest
@testable import Astrid_App

final class DragNestingTests: XCTestCase {

    /// parent → child → grandchild, plus a second top-level task.
    private func tree() -> [String: Task] {
        var parent = Task(id: "p", title: "parent")
        var child = Task(id: "c", title: "child")
        var grand = Task(id: "g", title: "grandchild")
        let other = Task(id: "o", title: "other top level")
        parent.parentTaskId = nil
        child.parentTaskId = "p"
        grand.parentTaskId = "c"
        return Dictionary(uniqueKeysWithValues: [parent, child, grand, other].map { ($0.id, $0) })
    }

    // MARK: over a row → nest under it

    func testDroppingOnARowMakesItASubtaskOfThatRow() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outcome(for: .onRow("o"), dragged: byId["c"]!, byId: byId),
                       .makeSubtask(taskId: "c", parentId: "o"))
    }

    func testATaskCannotBecomeItsOwnSubtask() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outcome(for: .onRow("c"), dragged: byId["c"]!, byId: byId), .none)
    }

    /// Dropping a parent onto its own descendant would make a cycle — the list would lose both.
    func testATaskCannotBeNestedUnderItsOwnDescendant() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outcome(for: .onRow("g"), dragged: byId["p"]!, byId: byId), .none)
    }

    /// Already its parent: nothing to write.
    func testDroppingOnTheParentItAlreadyHasIsANoOp() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outcome(for: .onRow("p"), dragged: byId["c"]!, byId: byId), .none)
    }

    // MARK: the line between rows → top level

    func testDroppingOnTheLineMakesASubtaskTopLevel() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outcome(for: .betweenRows(above: "o"), dragged: byId["c"]!, byId: byId),
                       .moveToTopLevel(taskId: "c"))
    }

    /// The line is the reorder affordance too, so it is offered for every drag — but a task
    /// that is ALREADY top level has no parent to clear, and must not write null over null.
    func testDroppingATopLevelTaskOnTheLineReordersWithoutWritingAParent() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outcome(for: .betweenRows(above: "p"), dragged: byId["o"]!, byId: byId),
                       .reorderOnly(taskId: "o"))
    }

    func testTheLineAboveTheFirstRowAlsoPromotes() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outcome(for: .betweenRows(above: nil), dragged: byId["g"]!, byId: byId),
                       .moveToTopLevel(taskId: "g"))
    }

    // MARK: dragged left → outdent one level

    /// Depth 1: one level out IS top level — the case the request describes.
    func testOutdentingADirectSubtaskReachesTopLevel() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outdent(byId["c"]!, byId: byId), .moveToTopLevel(taskId: "c"))
    }

    /// Deeper than 1: one level per drag, the outliner convention. Jumping a depth-3 task
    /// straight to the top from one sideways nudge is a surprise that is awkward to undo.
    func testOutdentingAGrandchildMovesItUnderItsGrandparent() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outdent(byId["g"]!, byId: byId),
                       .makeSubtask(taskId: "g", parentId: "p"))
    }

    func testATopLevelTaskHasNothingToOutdent() {
        let byId = tree()
        XCTAssertEqual(DragNesting.outdent(byId["o"]!, byId: byId), .none)
    }

    // MARK: the sideways gesture itself

    func testDraggingFarEnoughLeftIsAnOutdent() {
        XCTAssertTrue(DragNesting.isOutdentDrag(horizontalTranslation: -DragNesting.outdentDragThreshold))
        XCTAssertTrue(DragNesting.isOutdentDrag(horizontalTranslation: -200))
    }

    /// A drag is never purely vertical, so a small sideways wobble during a reorder must not
    /// silently re-nest the task.
    func testASmallSidewaysWobbleIsNotAnOutdent() {
        XCTAssertFalse(DragNesting.isOutdentDrag(horizontalTranslation: -5))
        XCTAssertFalse(DragNesting.isOutdentDrag(horizontalTranslation: 0))
    }

    /// Rightwards is indent territory, not outdent — it must never be read as one.
    func testDraggingRightIsNeverAnOutdent() {
        XCTAssertFalse(DragNesting.isOutdentDrag(horizontalTranslation: 200))
    }

    // MARK: what actually gets written

    /// The outcome has to survive the trip to TaskService, and clearing a parent is spelled
    /// with the empty string — nil there means "leave unchanged".
    func testMoveToTopLevelWritesTheClearingValue() {
        XCTAssertEqual(DragNesting.parentIdToWrite(for: .moveToTopLevel(taskId: "c")),
                       SubtaskPromotion.clearParentValue)
    }

    func testMakeSubtaskWritesTheNewParent() {
        XCTAssertEqual(DragNesting.parentIdToWrite(for: .makeSubtask(taskId: "g", parentId: "p")), "p")
    }

    func testAReorderOrNoOpWritesNothing() {
        XCTAssertNil(DragNesting.parentIdToWrite(for: .reorderOnly(taskId: "o")))
        XCTAssertNil(DragNesting.parentIdToWrite(for: .none))
    }

    // MARK: which zone a drop landed in

    /// iOS has no separate line view — an overlay with a hit shape on every row is how you
    /// swallow taps, which this codebase has paid for more than once. The drop location
    /// picks the zone instead, so the row itself is the only target.
    func testADropNearTheTopOfARowIsTheLineAboveIt() {
        XCTAssertEqual(DragNesting.zone(forDropAtY: 2, rowHeight: 60, rowId: "c"),
                       .betweenRows(above: "c"))
    }

    func testADropInTheBodyOfARowNestsUnderIt() {
        XCTAssertEqual(DragNesting.zone(forDropAtY: 30, rowHeight: 60, rowId: "c"),
                       .onRow("c"))
        XCTAssertEqual(DragNesting.zone(forDropAtY: 58, rowHeight: 60, rowId: "c"),
                       .onRow("c"))
    }

    /// The band has to be reachable with a finger but must not eat the whole row.
    func testTheLineBandIsAMinorityOfTheRow() {
        let height: CGFloat = 60
        let band = DragNesting.lineBandHeight(rowHeight: height)
        XCTAssertGreaterThanOrEqual(band, 8, "Has to be hittable")
        XCTAssertLessThan(band, height / 2, "The row itself must stay the bigger target")
    }

    /// A very short row must still leave most of itself as the nest target.
    func testTheBandNeverSwallowsAShortRow() {
        let height: CGFloat = 20
        XCTAssertLessThan(DragNesting.lineBandHeight(rowHeight: height), height / 2)
    }

    // MARK: indent — the other direction, for the keyboard

    /// Indent nests a task under its PREVIOUS SIBLING, the outliner convention. The row above
    /// is not always the right answer: it may be a deeper descendant of something else.
    func testIndentNestsUnderThePreviousSibling() {
        let byId = tree()
        // rendered order: p, c, g, o — `o` is top level and `p` is its previous sibling.
        let rows = ["p", "c", "g", "o"].map { byId[$0]! }
        XCTAssertEqual(DragNesting.indent(byId["o"]!, in: rows, byId: byId),
                       .makeSubtask(taskId: "o", parentId: "p"))
    }

    /// A first child has no previous sibling, so there is nothing to nest under.
    func testTheFirstChildCannotIndentFurther() {
        let byId = tree()
        let rows = ["p", "c", "g", "o"].map { byId[$0]! }
        XCTAssertEqual(DragNesting.indent(byId["c"]!, in: rows, byId: byId), .none)
    }

    /// The very first row has nothing above it at all.
    func testTheFirstRowCannotIndent() {
        let byId = tree()
        let rows = ["p", "c", "g", "o"].map { byId[$0]! }
        XCTAssertEqual(DragNesting.indent(byId["p"]!, in: rows, byId: byId), .none)
    }

    /// Indent and outdent must round-trip: nesting a task under its previous sibling and then
    /// outdenting it puts the parent back exactly where it was.
    func testIndentThenOutdentReturnsTheTaskToItsOriginalParent() {
        let byId = tree()
        let rows = ["p", "c", "g", "o"].map { byId[$0]! }
        guard case .makeSubtask(_, let newParent) = DragNesting.indent(byId["o"]!, in: rows, byId: byId) else {
            return XCTFail("expected o to indent under p")
        }
        var moved = byId["o"]!
        moved.parentTaskId = newParent
        var after = byId
        after["o"] = moved
        XCTAssertEqual(DragNesting.outdent(moved, byId: after), .moveToTopLevel(taskId: "o"))
    }
}
