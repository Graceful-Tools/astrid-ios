//  MacCommentSendButtonTests.swift
//  Regression guard for Task AITD-303 — "[mac] add attachment timer button should be a publish
//  button (blue send button like iOS) when there is an attachment and/or text in the add comment
//  so the user can press enter (currently works) or press the button to send."
//
//  Return posted the comment and nothing else did. The footer's trailing slot was permanently the
//  timer, so a staged screenshot sat there with no visible way to send it — the affordance for the
//  most common action in the panel was a keystroke you had to already know about.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacCommentSendButtonTests: XCTestCase {

    private func detailSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views/MacTaskDetailView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - When Send appears

    /// Text alone is enough — the case Return already handled.
    func testTypedTextOffersSend() {
        XCTAssertTrue(MacCommentSend.showsSend(text: "send", stagedCount: 0))
    }

    /// A staged file alone is enough. This is the reported case: a screenshot picked with the
    /// paperclip, nothing typed, and no button to post it.
    func testAStagedFileAloneOffersSend() {
        XCTAssertTrue(MacCommentSend.showsSend(text: "", stagedCount: 1),
                      "An attachment with no caption is a postable comment — that is the whole point of staging")
    }

    func testTextAndFileTogetherOfferSend() {
        XCTAssertTrue(MacCommentSend.showsSend(text: "here", stagedCount: 2))
    }

    /// Empty composer keeps the timer, which is what that slot is for.
    func testEmptyComposerKeepsTheTimer() {
        XCTAssertFalse(MacCommentSend.showsSend(text: "", stagedCount: 0))
        XCTAssertFalse(MacCommentSend.showsSend(text: "   \n\t", stagedCount: 0),
                       "Whitespace is not a comment — Send would post nothing")
    }

    // MARK: - The invariant that matters

    /// An offered Send must actually post. `addComment()` guards on "text or a staged file", so
    /// the button's condition has to be the SAME predicate — a Send that no-ops on click is worse
    /// than no Send at all.
    func testSendIsOfferedExactlyWhenPostingWouldDoSomething() {
        for text in ["", "  ", "hello"] {
            for staged in 0...2 {
                XCTAssertEqual(MacCommentSend.showsSend(text: text, stagedCount: staged),
                               MacCommentSend.canPost(text: text, stagedCount: staged),
                               "Send must be offered exactly when a post would happen (text: \(text.debugDescription), staged: \(staged))")
            }
        }
    }

    // MARK: - The button itself

    /// Blue send, like iOS: the accent-tinted paperplane, wired to the same `addComment` Return
    /// calls — not a second posting path that can drift from it.
    func testTheTrailingSlotBecomesAnAccentSendButton() throws {
        let source = try detailSource()
        XCTAssertTrue(source.contains("MacCommentSend.showsSend"),
                      "The footer must ask the shared rule which button to show")
        XCTAssertTrue(source.contains("paperplane.fill"),
                      "iOS's send glyph — the two composers should not look like different apps")
        XCTAssertTrue(source.contains("Button(action: addComment)"),
                      "Send must call the same addComment() that Return does")
    }

    /// Return keeps working. It was the only way to post before this task and must not become a
    /// casualty of adding the button.
    func testReturnStillPosts() throws {
        let source = try detailSource()
        XCTAssertTrue(source.contains(".onSubmit(addComment)"),
                      "Return must still post — the button is an addition, not a replacement")
    }
}
#endif
