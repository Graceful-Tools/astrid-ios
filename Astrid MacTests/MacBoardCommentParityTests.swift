//  MacBoardCommentParityTests.swift
//  Regression guard for Task AITD-432 — "[mac] paste image from clipboard doesn't work in Add
//  comment in board view. review and reuse so capabilities don't drift between board view task
//  details and list view task details."
//
//  The board card carried its own comment box. It was written before AITD-306 (⌘V attaches),
//  AITD-303 (Send button), 3b3d70ce (stage, then post), eda86d23 (@-autocomplete), AITD-304
//  (a comment draws its files) and AITD-389 (a comment is markdown) — and received none of them,
//  because each landed in MacTaskDetailView and the card was a second implementation nobody
//  opened. The paste was only the one Jon hit first.
//
//  So the fix is not a second paste monitor. Both surfaces draw the SAME composer and the SAME
//  thread, and these assertions keep it that way.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardCommentParityTests: XCTestCase {

    private func macSource(_ relative: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(relative), encoding: .utf8)
    }

    private let board = "Astrid Mac/Views/MacBoardCardEditor.swift"
    private let detail = "Astrid Mac/Views/MacTaskDetailView.swift"

    /// The report: ⌘V with a screenshot in the board card's comment field did nothing, because the
    /// card never installed the paste handling the detail has. It gets it by drawing the shared
    /// composer, which owns that handling.
    func testBoardCardUsesTheSharedComposer() throws {
        for path in [board, detail] {
            XCTAssertTrue(try macSource(path).contains("MacCommentComposerBar("),
                          "\(path) must draw the shared comment composer — paste, staging, Send and autocomplete live there")
        }
    }

    /// The comments themselves: files, markdown, folded completion runs, hidden system comments,
    /// edit/delete of your own. The card drew `Text(c.content)` and nothing else.
    func testBoardCardUsesTheSharedThread() throws {
        for path in [board, detail] {
            XCTAssertTrue(try macSource(path).contains("MacCommentThreadList("),
                          "\(path) must draw comments through the shared thread list")
        }
        XCTAssertFalse(try macSource(board).contains("Text(c.content)"),
                       "a plain-text comment row is the drift this task removes")
    }

    /// No surface posts a comment or reads the pasteboard on its own — that is how the card fell
    /// behind. One place creates comments from the composer, and one place watches for ⌘V.
    func testNeitherSurfaceKeepsItsOwnCopyOfThePipeline() throws {
        for path in [board, detail] {
            let source = try macSource(path)
            XCTAssertFalse(source.contains("CommentService.shared.createComment"),
                           "\(path) posts comments itself — route it through the shared composer")
            XCTAssertFalse(source.contains("addLocalMonitorForEvents"),
                           "\(path) watches ⌘V itself — the shared composer owns the paste monitor")
        }
    }

    /// The paperclip on the card used to POST immediately with the filename as the body — the
    /// behaviour 3b3d70ce removed from the detail. The shared composer stages instead.
    func testBoardPaperclipStagesRatherThanPosting() throws {
        XCTAssertFalse(try macSource(board).contains("NSOpenPanel"),
                       "the card must not keep its own file picker; the composer's stages the file")
    }
}
#endif
