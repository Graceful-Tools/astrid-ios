//  BoardCardMoveFollowTests.swift
//  ADEV-175: "when completing a task on the board, update where the arrow on the task details
//  points so it points to the moved task item (e.g. points to the done column and the task). When
//  marking as to-do, do the same, moving the arrow and scrolling the board horizontally."
//  The open card moving to another column is told apart from another task being opened, the board
//  scrolls the new column clear of the panel, and the moved card's position survives the old card
//  leaving the column it came from.

import XCTest
@testable import Astrid_App

@MainActor
final class BoardCardMoveFollowTests: XCTestCase {

    // MARK: - A move, not a new selection

    func testCompletingTheOpenCardIsAMoveIntoDone_ADEV175() {
        let before = BoardCardCallout.Spot(taskId: "t", columnId: "doing")
        let after = BoardCardCallout.Spot(taskId: "t", columnId: "done")
        XCTAssertEqual(BoardCardCallout.moved(from: before, to: after), after)
    }

    func testMarkingItToDoIsAMoveOutOfDone_ADEV175() {
        let before = BoardCardCallout.Spot(taskId: "t", columnId: "done")
        let after = BoardCardCallout.Spot(taskId: "t", columnId: "inbox")
        XCTAssertEqual(BoardCardCallout.moved(from: before, to: after), after)
    }

    func testOpeningAnotherTaskOrStayingPutIsNotAMove_ADEV175() {
        let a = BoardCardCallout.Spot(taskId: "a", columnId: "doing")
        XCTAssertNil(BoardCardCallout.moved(from: a, to: .init(taskId: "b", columnId: "done")))
        XCTAssertNil(BoardCardCallout.moved(from: a, to: a))
        XCTAssertNil(BoardCardCallout.moved(from: nil, to: a), "opening the panel is not a move")
        XCTAssertNil(BoardCardCallout.moved(from: a, to: nil), "closing it is not a move")
    }

    // MARK: - Scrolling the new column into view

    private let board = CGRect(x: 0, y: 0, width: 1180, height: 820)

    func testACardOpenedOnTheLeftKeepsItsNewColumnOnTheLeft_ADEV175() {
        // Its panel is on the right, so the column it moved into scrolls to the leading edge.
        let card = CGRect(x: 16, y: 200, width: 280, height: 72)
        XCTAssertEqual(BoardCardCallout.scrollEdge(openedCard: card, board: board), .leading)
    }

    func testACardOpenedOnTheRightKeepsItsNewColumnOnTheRight_ADEV175() {
        let card = CGRect(x: 884, y: 200, width: 280, height: 72)
        XCTAssertEqual(BoardCardCallout.scrollEdge(openedCard: card, board: board), .trailing)
    }

    func testNoOpenedCardScrollsToTheLeadingEdge_ADEV175() {
        XCTAssertEqual(BoardCardCallout.scrollEdge(openedCard: nil, board: board), .leading)
    }

    // MARK: - The reporter follows the card to its new column

    func testTheOldCardLeavingDoesNotEraseTheMovedCardsFrame_ADEV175() {
        let reporter = SelectedRowReporter()
        let inDoing = CGRect(x: 16, y: 200, width: 280, height: 72)
        let inDone = CGRect(x: 900, y: 120, width: 280, height: 72)
        reporter.openCard(taskId: "t", frame: inDoing, source: "card-in-doing")
        // The card is drawn in Done before the Doing card's onDisappear runs.
        reporter.reportCard(taskId: "t", frame: inDone, source: "card-in-done")
        reporter.clear(taskId: "t", source: "card-in-doing")
        XCTAssertEqual(reporter.cardFrame, inDone, "the arrow keeps pointing at the card in Done")
        XCTAssertEqual(reporter.midY, inDone.midY)
    }

    func testTheCardItselfLeavingStillClears_ADEV175() {
        let reporter = SelectedRowReporter()
        reporter.openCard(taskId: "t", frame: CGRect(x: 0, y: 0, width: 10, height: 10), source: "x")
        reporter.clear(taskId: "t", source: "x")
        XCTAssertNil(reporter.cardFrame)
    }

    func testReanchoringDocksThePanelBesideTheMovedCard_ADEV175() {
        let reporter = SelectedRowReporter()
        let inDoing = CGRect(x: 16, y: 200, width: 280, height: 72)
        let inDone = CGRect(x: 16, y: 120, width: 280, height: 72)
        reporter.openCard(taskId: "t", frame: inDoing, source: "a")
        reporter.reportCard(taskId: "t", frame: inDone, source: "b")
        XCTAssertEqual(reporter.openedCard?.frame, inDoing, "a scroll alone does not move the panel")
        reporter.reanchorOpenedCard(taskId: "t")
        XCTAssertEqual(reporter.openedCard, .init(taskId: "t", frame: inDone))
    }

    func testReanchoringIgnoresAnotherTask_ADEV175() {
        let reporter = SelectedRowReporter()
        let frame = CGRect(x: 16, y: 200, width: 280, height: 72)
        reporter.openCard(taskId: "t", frame: frame, source: "a")
        reporter.reanchorOpenedCard(taskId: "other")
        XCTAssertEqual(reporter.openedCard, .init(taskId: "t", frame: frame))
    }
}
