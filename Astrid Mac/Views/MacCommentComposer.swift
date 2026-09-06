//  MacCommentComposer.swift
//  Astrid for Mac — what the comment field's trailing button is (Task AITD-303).
//
//  The footer's trailing slot was always the timer. Return posted the comment and nothing else
//  did, so a comment with a staged screenshot in it had no visible way out — you had to know
//  about Return. iOS puts a send button beside the paperclip; the Mac now gives that slot to
//  Send the moment there is something to send, and hands it back to the timer when there isn't.
//
//  Pure so the "when" is testable without a view: it is the same predicate `addComment()` guards
//  on, which is the property that matters — a button that is offered must actually post.

#if os(macOS)
import Foundation

enum MacCommentSend {
    /// Either text or a staged file is enough to post; neither is not. Identical to the guard in
    /// `addComment()` on purpose — an offered Send that does nothing is worse than no Send.
    static func canPost(text: String, stagedCount: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || stagedCount > 0
    }

    /// The trailing slot shows Send while there is something to send, and the timer otherwise.
    /// Stopping a running timer does not depend on this button: while a timer runs the detail
    /// shows its own Timer section with Stop (MacTimerSection.showsSection).
    static func showsSend(text: String, stagedCount: Int) -> Bool {
        canPost(text: text, stagedCount: stagedCount)
    }
}
#endif
