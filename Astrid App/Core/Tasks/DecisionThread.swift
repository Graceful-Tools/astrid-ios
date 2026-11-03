//  DecisionThread.swift
//  Whether a question asked in a comment is still open, and what answered it (AITD-579).
//
//  An agent's question is an ordinary comment; its `**Decision:**` options draw as cards
//  (`Decisions` in AstridCore). Tapping one posts its number and words as an ordinary reply — the
//  reply that already wakes the agent — so the server holds no decision state, and the thread is
//  the only record of whether one was made. These rules read it, for iOS and the Mac alike.

import AstridCore
import Foundation

enum DecisionThread {

    /// The first comment after `asked` from someone other than its author, or `nil` while
    /// nobody has replied. A system line and the asker's own follow-up are not answers.
    static func answer(to asked: Comment, in comments: [Comment]) -> Comment? {
        guard let position = comments.firstIndex(where: { $0.id == asked.id }) else { return nil }
        return comments[comments.index(after: position)...]
            .filter { isLater($0, than: asked) }
            .first { reply in
                !CommentVisibility.isSystem(reply, isOffline: false) && reply.authorId != asked.authorId
            }
    }

    /// Threads arrive in order; a timestamp, where both have one, settles a row out of place.
    private static func isLater(_ reply: Comment, than asked: Comment) -> Bool {
        guard let replied = reply.createdAt, let at = asked.createdAt else { return true }
        return replied >= at
    }
}

/// What a comment thread hands the decision cards it draws: the reply that answered the question,
/// if any, and how to answer it. A description has none, so its cards only show the options.
struct DecisionResponse {
    let answer: Comment?
    let choose: (DecisionOption) -> Void

    enum State: Equatable {
        /// No thread to answer in, or the viewer asked the question.
        case readOnly
        case open
        /// The chosen option's number (AITD-585).
        case chosen(Int)
        /// Someone replied without leading with a letter.
        case answeredInWords
    }

    func state(for decision: Decision) -> State {
        guard let answer else { return .open }
        return Decisions.chosenNumber(in: answer.content, options: decision.options).map(State.chosen)
            ?? .answeredInWords
    }

    /// A tap sends at once, on iPhone as on the Mac (AITD-584): the reply shows in the thread and
    /// can be edited there, so a confirmation sheet only slowed the answer down.
    func tap(_ option: DecisionOption, in decision: Decision) {
        guard state(for: decision) == .open else { return }
        choose(option)
    }

    static func state(_ response: DecisionResponse?, for decision: Decision) -> State {
        response?.state(for: decision) ?? .readOnly
    }
}
