//  EditingSessionTests.swift
//  Task 55010e29 — "One editing session at a time on iOS + Mac".
//
//  Today every editor owns an `isEditing` flag and its own save semantics: some commit on Done,
//  some on resign, some offer Cancel, some auto-save on disappear. Two can be open at once —
//  edit a list, tap the title. The keyboard-dismissal fix in build 175 was this same rule
//  applied by hand at one call site, which is the smell: the rule exists, it just is not
//  written down anywhere. The `!showingCustomEditor` regression was two paths for one decision
//  drifting apart.
//
//  This pins the coordinator as a state machine BEFORE any view adopts it. The transitions
//  below are the ones a per-editor boolean cannot express — particularly the two ordering
//  hazards (re-entrant begin, and a late teardown from a view that is already gone), which is
//  where hand-rolled exclusivity corrupts itself.

import XCTest
@testable import Astrid_App

@MainActor
final class EditingSessionTests: XCTestCase {

    /// Records what the coordinator asked of each editor, in order.
    private final class Recorder {
        enum Event: Equatable { case commit(String), cancel(String) }
        var events: [Event] = []
        var committed: [String] { events.compactMap { if case .commit(let id) = $0 { return id } else { return nil } } }
        var cancelled: [String] { events.compactMap { if case .cancel(let id) = $0 { return id } else { return nil } } }
    }

    private func session(_ recorder: Recorder) -> EditingSession {
        EditingSession(
            onCommit: { recorder.events.append(.commit($0)) },
            onCancel: { recorder.events.append(.cancel($0)) }
        )
    }

    // MARK: - Exclusivity

    /// THE RULE: exactly one editor is active.
    func testBeginningASecondEditorMakesItTheOnlyActiveOne() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.begin("dueDate")

        XCTAssertEqual(session.activeEditor, "dueDate")
        XCTAssertTrue(session.isActive("dueDate"))
        XCTAssertFalse(session.isActive("title"), "two editors were open at once — the reported bug")
    }

    /// Click-out-to-save: opening another editor SAVES the one it displaced. It must not
    /// silently discard what was typed.
    func testOpeningAnotherEditorCommitsTheDisplacedOne() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.begin("dueDate")

        XCTAssertEqual(recorder.committed, ["title"])
        XCTAssertTrue(recorder.cancelled.isEmpty, "displacing an editor must never discard its edit")
    }

    // MARK: - Ordering hazards

    /// HAZARD 1 — re-entrant begin. A view re-render calling begin on the ALREADY active editor
    /// must be a no-op. Treating it as a displacement would fire a commit on every redraw.
    func testBeginningTheAlreadyActiveEditorDoesNothing() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.begin("title")

        XCTAssertEqual(session.activeEditor, "title")
        XCTAssertTrue(recorder.events.isEmpty, "a re-render must not commit")
    }

    /// HAZARD 2 — a late teardown. A dismissed editor's `end` can arrive AFTER another editor
    /// has become active (SwiftUI tears views down asynchronously). It must not clear the new
    /// one, or the active editor is silently deactivated while still on screen.
    func testALateEndFromAnOldEditorDoesNotDisturbTheActiveOne() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.begin("dueDate")   // commits "title"
        session.end("title")       // arrives late, from a view already gone

        XCTAssertEqual(session.activeEditor, "dueDate", "the live editor was deactivated by a ghost")
        XCTAssertEqual(recorder.committed, ["title"], "and it must not commit 'title' twice")
    }

    // MARK: - Ending and cancelling

    func testEndingTheActiveEditorCommitsAndClears() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.end("title")

        XCTAssertNil(session.activeEditor)
        XCTAssertEqual(recorder.committed, ["title"])
    }

    /// Cancel is the ONLY path that does not save.
    func testCancellingRevertsAndDoesNotCommit() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.cancel("title")

        XCTAssertNil(session.activeEditor)
        XCTAssertEqual(recorder.cancelled, ["title"])
        XCTAssertTrue(recorder.committed.isEmpty)
    }

    /// A cancel aimed at an editor that is no longer active must not touch the live one either.
    func testALateCancelDoesNotDisturbTheActiveEditor() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.begin("dueDate")
        session.cancel("title")

        XCTAssertEqual(session.activeEditor, "dueDate")
        XCTAssertTrue(recorder.cancelled.isEmpty, "'title' already committed when it was displaced")
    }

    // MARK: - Leaving

    /// Navigating away or backgrounding commits whatever is open — the same click-out rule.
    func testCommittingEverythingSavesTheActiveEditor() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("description")
        session.commitAll()

        XCTAssertNil(session.activeEditor)
        XCTAssertEqual(recorder.committed, ["description"])
    }

    /// …and is safe when nothing is open, so a view can call it unconditionally on disappear.
    func testCommittingEverythingWithNothingOpenIsSafe() {
        let recorder = Recorder()
        let session = session(recorder)

        session.commitAll()

        XCTAssertNil(session.activeEditor)
        XCTAssertTrue(recorder.events.isEmpty)
    }

    /// A full sequence, since the bug is about editors interacting rather than any one of them.
    func testASequenceOfEditsCommitsEachExactlyOnce() {
        let recorder = Recorder()
        let session = session(recorder)

        session.begin("title")
        session.begin("dueDate")
        session.begin("assignee")
        session.commitAll()

        XCTAssertEqual(recorder.committed, ["title", "dueDate", "assignee"])
        XCTAssertNil(session.activeEditor)
    }
}
