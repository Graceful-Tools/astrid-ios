//  AppCoreRoutingTests.swift
//  Each change reaches only the services it concerns (AITD-454).
//
//  Every change used to go to all six services. A delivered task edit arrived as "something moved,
//  cannot say what", so TaskService read every task (up to three times), CommentService and
//  ChatService re-read every thread and channel opened this session, lists, boards and rosters
//  reloaded, and three services asked for the journal's counts — on every write.

import XCTest
import AstridCore
@testable import Astrid_App

final class AppCoreRoutingTests: XCTestCase {

    private func delivery(
        tasks: [String] = [], lists: [String] = [], comments: [String] = [], channels: [String] = [],
        undescribed: Bool = false
    ) -> CoreChange {
        .delivered(CoreDelivery(taskIds: tasks, listIds: lists, commentTaskIds: comments,
                                channelIds: channels, undescribed: undescribed,
                                pending: 0, running: 0, failed: 0))
    }

    /// AITD-454: the case the audit measured. One task edit delivered reaches TaskService alone.
    func testADeliveredTaskEditReachesOnlyTasks_AITD454() {
        XCTAssertEqual(AppCore.audiences(for: delivery(tasks: ["t1"])), [.tasks])
    }

    func testADeliveredCommentReachesOnlyComments_AITD454() {
        XCTAssertEqual(AppCore.audiences(for: delivery(comments: ["t1"])), [.comments])
        XCTAssertEqual(AppCore.audiences(for: delivery(channels: ["c1"])), [.chat])
    }

    func testADeliveredListChangeReachesListsRostersAndBoards_AITD454() {
        XCTAssertEqual(AppCore.audiences(for: delivery(lists: ["l1"])), [.lists, .members, .projects])
    }

    /// A settings write settles with nothing to re-read: the counts go out, nothing reloads.
    func testADeliveryThatTouchedNothingReloadsNothing_AITD454() {
        XCTAssertEqual(AppCore.audiences(for: delivery()), [])
    }

    /// What a service cannot tell is still handled: everyone hears it.
    func testWhatCannotBeDescribedStillReachesEveryone_AITD454() {
        XCTAssertEqual(AppCore.audiences(for: delivery(undescribed: true)), Set(AppCore.Audience.allCases))
        XCTAssertEqual(AppCore.audiences(for: .unknown("{}")), Set(AppCore.Audience.allCases))
        XCTAssertEqual(AppCore.audiences(for: .synced(taskIds: [], listIds: [])),
                       Set(AppCore.Audience.allCases))
    }

    /// A pass that names what it pulled reaches tasks only when tasks moved; the boards ride on
    /// every pass because their sync reports nothing.
    func testASyncPassReachesWhatItNamed_AITD454() {
        XCTAssertEqual(AppCore.audiences(for: .synced(taskIds: ["t1"], listIds: [])), [.tasks, .projects])
        XCTAssertEqual(AppCore.audiences(for: .synced(taskIds: [], listIds: ["l1"])),
                       [.lists, .members, .projects])
    }

    /// The stream's single-row events go where they always did, and nowhere else.
    func testTheStreamsEventsReachTheirOwnService_AITD454() {
        XCTAssertEqual(AppCore.audiences(for: .task(id: "t1")), [.tasks])
        XCTAssertEqual(AppCore.audiences(for: .list(id: "l1")), [.lists, .members])
        XCTAssertEqual(AppCore.audiences(for: .comments(taskId: "t1")), [.comments])
        XCTAssertEqual(AppCore.audiences(for: .chat(channelId: "c1")), [.chat])
        XCTAssertEqual(AppCore.audiences(for: .settings), [.lists])
        XCTAssertEqual(AppCore.audiences(for: .needsSync), [.tasks])
        XCTAssertEqual(AppCore.audiences(for: .notifications), [])
        XCTAssertEqual(AppCore.audiences(for: .remindersDue), [])
        XCTAssertEqual(AppCore.audiences(for: .stream(live: true)), [])
    }
}
