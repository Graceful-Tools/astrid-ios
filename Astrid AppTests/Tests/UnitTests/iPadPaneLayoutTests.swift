//  iPadPaneLayoutTests.swift
//  Regression tests for Task a34d0163 — "iPad 2 column and iPad 3 column do not perform as
//  advertised".
//
//  The advertised behaviour: 2 column = task list + list messages, with task details appearing
//  OVER the messages; 3 column = list picker + task list + list messages. What shipped had no
//  messages column at all — `showChatPanel` was never set true, so the pane was dead code.
//
//  These pin the layout as a pure function, because the failure was a rule nobody could see:
//  a width table and a "does this pane show here?" decision spread across two view builders.

import XCTest
@testable import Astrid_App

final class iPadPaneLayoutTests: XCTestCase {

    private let width: CGFloat = 1194   // iPad Pro 11" landscape

    // MARK: the messages pane exists at all (the bug)

    /// The whole complaint: a list in list view must show its messages beside it.
    func testListViewShowsMessagesInBothLayouts() {
        for columns in [2, 3] {
            XCTAssertTrue(iPadPaneLayout.showsMessages(columns: columns, viewMode: .list,
                                                       listId: "list-1", boardFullScreen: false),
                          "\(columns)-column list view must show list messages")
        }
    }

    /// "Board view is fine" — the board keeps the room, so messages stand down there.
    func testBoardModeHidesMessages() {
        XCTAssertFalse(iPadPaneLayout.showsMessages(columns: 3, viewMode: .board,
                                                    listId: "list-1", boardFullScreen: false))
    }

    /// Virtual lists with no chat channel must not show an empty pane. My Tasks HAS one
    /// (ChatPanelView resolves a virtual channel), so it is the exception that must stay.
    func testOnlyListsWithAChannelShowMessages() {
        for listId in ["search", "shared", "favorites", "settings", "profile"] {
            XCTAssertFalse(iPadPaneLayout.showsMessages(columns: 3, viewMode: .list,
                                                        listId: listId, boardFullScreen: false),
                           "\(listId) has no chat channel")
        }
        XCTAssertTrue(iPadPaneLayout.showsMessages(columns: 3, viewMode: .list,
                                                   listId: "my-tasks", boardFullScreen: false),
                      "My Tasks has a virtual channel")
        XCTAssertFalse(iPadPaneLayout.showsMessages(columns: 3, viewMode: .list,
                                                    listId: nil, boardFullScreen: false))
    }

    // MARK: widths

    /// Every pane in view has to add up to the screen, or a column gets clipped off the edge.
    func testPanesFillExactlyTheAvailableWidth() {
        for columns in [2, 3] {
            for messages in [true, false] {
                let panes = iPadPaneLayout.widths(total: width, columns: columns,
                                                  showsMessages: messages, boardFullScreen: false)
                XCTAssertEqual(panes.sidebar + panes.list + panes.messages, width, accuracy: 0.5,
                               "\(columns)-column, messages=\(messages) does not fill the width")
            }
        }
    }

    /// 3 column is the only one that spends width on a permanently visible list picker; in
    /// 2 column the picker is the sliding drawer, so it takes no room.
    func testOnlyThreeColumnReservesTheListPicker() {
        XCTAssertGreaterThan(iPadPaneLayout.widths(total: width, columns: 3, showsMessages: true,
                                                   boardFullScreen: false).sidebar, 0)
        XCTAssertEqual(iPadPaneLayout.widths(total: width, columns: 2, showsMessages: true,
                                             boardFullScreen: false).sidebar, 0)
    }

    /// "Task details appearing over list messages" — the detail panel is exactly as wide as the
    /// messages pane it covers, so opening a task never hides the task list you are working in.
    func testDetailPanelExactlyCoversTheMessagesPane() {
        for columns in [2, 3] {
            let panes = iPadPaneLayout.widths(total: width, columns: columns, showsMessages: true,
                                              boardFullScreen: false)
            XCTAssertEqual(iPadPaneLayout.detailWidth(total: width, columns: columns,
                                                      showsMessages: true),
                           panes.messages, accuracy: 0.5,
                           "\(columns)-column detail must cover the messages pane exactly")
        }
    }

    /// With no messages pane there is nothing to cover, so the detail falls back to its own
    /// share rather than collapsing to zero.
    func testDetailStillHasWidthWithoutAMessagesPane() {
        for columns in [2, 3] {
            XCTAssertGreaterThan(iPadPaneLayout.detailWidth(total: width, columns: columns,
                                                            showsMessages: false), 0)
        }
    }

    /// The task list never loses its place to the messages pane.
    func testTheTaskListIsNeverNarrowerThanTheMessagesPane() {
        for columns in [2, 3] {
            let panes = iPadPaneLayout.widths(total: width, columns: columns, showsMessages: true,
                                              boardFullScreen: false)
            XCTAssertGreaterThanOrEqual(panes.list, panes.messages,
                                        "\(columns)-column: messages must not outgrow the list")
        }
    }

    // MARK: board full screen (item 4)

    /// Full screen means full screen: no picker, no messages, board takes the window.
    func testFullScreenBoardTakesTheWholeWindow() {
        let panes = iPadPaneLayout.widths(total: width, columns: 3, showsMessages: false,
                                          boardFullScreen: true)
        XCTAssertEqual(panes.list, width, accuracy: 0.5)
        XCTAssertEqual(panes.sidebar, 0)
        XCTAssertEqual(panes.messages, 0)
    }

    /// Full screen is a board affordance — it must not strip the picker off a list view.
    func testFullScreenOnlyAppliesToTheBoard() {
        XCTAssertGreaterThan(iPadPaneLayout.widths(total: width, columns: 3, showsMessages: true,
                                                   boardFullScreen: false).sidebar, 0)
        XCTAssertFalse(iPadPaneLayout.offersFullScreen(viewMode: .list))
        XCTAssertTrue(iPadPaneLayout.offersFullScreen(viewMode: .board))
    }

    /// A full-screen board cannot also be showing messages — belt and braces with the caller.
    func testFullScreenBoardHidesMessages() {
        XCTAssertFalse(iPadPaneLayout.showsMessages(columns: 3, viewMode: .board,
                                                    listId: "list-1", boardFullScreen: true))
    }

    // MARK: the rotator must not fight the pane

    /// Where messages are a pane, rotating into "messages" would replace the task list with a
    /// panel already on screen. The shared contract in getHeaderViewToggle already says this —
    /// it withholds .messages from any layout that is not one-column — and the rotator was the
    /// one place ignoring it.
    func testRotatorSkipsMessagesWhereTheyArePinnedBeside() {
        XCTAssertEqual(nextRotatorSegment(after: .list, hasBoard: true, includesMessages: false),
                       .board)
        XCTAssertEqual(nextRotatorSegment(after: .list, hasBoard: false, includesMessages: false),
                       .list, "nothing to rotate to; the caller hides the button")
        XCTAssertEqual(nextRotatorSegment(after: .board, hasBoard: true, includesMessages: false),
                       .list)
    }

    /// One-column keeps the three-way rotation it has always had.
    func testRotatorKeepsMessagesWhenTheyReplaceTheList() {
        XCTAssertEqual(nextRotatorSegment(after: .list, hasBoard: true, includesMessages: true),
                       .messages)
        XCTAssertEqual(nextRotatorSegment(after: .messages, hasBoard: true, includesMessages: true),
                       .board)
        XCTAssertEqual(nextRotatorSegment(after: .messages, hasBoard: false, includesMessages: true),
                       .list)
        XCTAssertEqual(nextRotatorSegment(after: .board, hasBoard: true, includesMessages: true),
                       .list)
    }

    /// The rotator's rule and the header contract must agree about when messages is a step.
    func testRotatorAgreesWithTheSharedHeaderContract() {
        let multiColumn = HeaderViewToggleState(isOneColumn: false, hasProjectBoard: true,
                                                chatAvailable: true, activeView: .list,
                                                isSearching: false)
        XCTAssertFalse(getHeaderViewToggle(multiColumn).segments.contains(.messages),
                       "contract: messages is not a segment on a multi-column layout")
        XCTAssertNotEqual(nextRotatorSegment(after: .list, hasBoard: true, includesMessages: false),
                          .messages)

        let oneColumn = HeaderViewToggleState(isOneColumn: true, hasProjectBoard: true,
                                              chatAvailable: true, activeView: .list,
                                              isSearching: false)
        XCTAssertTrue(getHeaderViewToggle(oneColumn).segments.contains(.messages))
        XCTAssertEqual(nextRotatorSegment(after: .list, hasBoard: true, includesMessages: true),
                       .messages)
    }
}
