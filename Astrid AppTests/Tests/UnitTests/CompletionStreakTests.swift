//  CompletionStreakTests.swift
//  Regression tests for Task dd3fda86 — "consolidate repeating task comments into a streak".
//
//  A repeating task appends a system comment on every rollover, so a daily task buries its real
//  conversation under a month of identical lines. These pin what may be folded, and — more
//  importantly — what may not.

import XCTest
@testable import Astrid_App

final class CompletionStreakTests: XCTestCase {

    private func system(_ content: String, daysAgo: Int) -> Comment {
        Comment(id: "sys-\(daysAgo)", content: content, type: .TEXT, authorId: nil, author: nil,
                taskId: "t1",
                createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()),
                updatedAt: nil)
    }

    private func completion(daysAgo: Int) -> Comment {
        system("Jon Paris marked this as complete", daysAgo: daysAgo)
    }

    private func userComment(_ content: String, daysAgo: Int) -> Comment {
        Comment(id: "usr-\(daysAgo)", content: content, type: .TEXT, authorId: "u1", author: nil,
                taskId: "t1",
                createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()),
                updatedAt: nil)
    }

    // MARK: what counts

    func testACompletionSystemCommentIsFoldable() {
        XCTAssertTrue(CompletionStreak.isCompletion(completion(daysAgo: 1)))
    }

    /// The whole point of the guard: a comment a PERSON wrote is never folded, even if they
    /// happen to type the same words.
    func testAUserCommentIsNeverFoldedEvenWithTheSameWords() {
        XCTAssertFalse(CompletionStreak.isCompletion(
            userComment("I marked this as complete by accident", daysAgo: 1)))
    }

    /// Other system comments are not completions — folding "moved to list" into a completion
    /// streak would be a lie about what happened.
    func testOtherSystemCommentsAreNotCompletions() {
        XCTAssertFalse(CompletionStreak.isCompletion(system("Jon Paris changed priority from ! to !!", daysAgo: 1)))
        XCTAssertFalse(CompletionStreak.isCompletion(system("Jon Paris marked this as incomplete", daysAgo: 1)))
    }

    // MARK: folding

    func testARunOfCompletionsBecomesOneStreak() {
        let items = CompletionStreak.fold((1...6).map { completion(daysAgo: $0) })
        XCTAssertEqual(items.count, 1)
        guard case .streak(let s) = items[0] else { return XCTFail("expected a streak") }
        XCTAssertEqual(s.count, 6)
    }

    /// Below the threshold nothing is folded — two lines collapsed into "completed 2 times" hides
    /// as much as it saves.
    func testAShortRunIsLeftAlone() {
        let items = CompletionStreak.fold([completion(daysAgo: 1), completion(daysAgo: 2)])
        XCTAssertEqual(items.count, 2)
        for item in items {
            guard case .comment = item else { return XCTFail("nothing this short should fold") }
        }
    }

    /// A real comment inside a run splits it: the conversation around it is exactly what this
    /// feature exists to keep readable.
    func testAUserCommentSplitsTheRun() {
        let items = CompletionStreak.fold([
            completion(daysAgo: 1), completion(daysAgo: 2), completion(daysAgo: 3),
            userComment("this one was hard", daysAgo: 4),
            completion(daysAgo: 5), completion(daysAgo: 6), completion(daysAgo: 7),
        ])
        XCTAssertEqual(items.count, 3)
        guard case .streak = items[0], case .comment = items[1], case .streak = items[2] else {
            return XCTFail("expected streak / comment / streak, got \(items)")
        }
    }

    /// Folding must never lose or reorder anything a person can read.
    func testNothingIsLost() {
        let comments = [
            userComment("first", daysAgo: 1),
            completion(daysAgo: 2), completion(daysAgo: 3), completion(daysAgo: 4),
            userComment("last", daysAgo: 5),
        ]
        let items = CompletionStreak.fold(comments)
        let recovered: [Comment] = items.flatMap { item -> [Comment] in
            switch item {
            case .comment(let c): return [c]
            case .streak(let s):  return s.completions
            }
        }
        XCTAssertEqual(recovered.map(\.id), comments.map(\.id))
    }

    func testAnEmptyListFoldsToNothing() {
        XCTAssertTrue(CompletionStreak.fold([]).isEmpty)
    }

    // MARK: the summary

    func testSummaryReportsCountAndSpan() {
        let streak = CompletionStreak.Streak(completions: (1...6).map { completion(daysAgo: $0 * 5) })
        XCTAssertEqual(streak.count, 6)
        XCTAssertEqual(streak.spanInDays, 25)   // 5 days ago → 30 days ago
        let summary = CompletionStreak.summary(for: streak)
        XCTAssertTrue(summary.contains("6"), "summary should name the count: \(summary)")
        XCTAssertFalse(summary.hasPrefix("comments.streak"), "unresolved key: \(summary)")
    }

    /// Completions land at whatever time of day the box was ticked, so the span must be counted
    /// in CALENDAR days. Measured as elapsed time it truncates — a run spanning 25 calendar days
    /// but 25-days-minus-a-moment of elapsed time floors to 24 and reads a day short.
    func testSpanCountsCalendarDaysNotElapsedTime() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 8))!
        let streak = CompletionStreak.Streak(completions: [
            Comment(id: "a", content: "marked this as complete", type: .TEXT, authorId: nil,
                    author: nil, taskId: "t1", createdAt: start, updatedAt: nil),
            Comment(id: "b", content: "marked this as complete", type: .TEXT, authorId: nil,
                    author: nil, taskId: "t1", createdAt: end, updatedAt: nil),
            Comment(id: "c", content: "marked this as complete", type: .TEXT, authorId: nil,
                    author: nil, taskId: "t1", createdAt: end, updatedAt: nil),
        ])
        XCTAssertEqual(streak.spanInDays, 30, "23 hours short of 30 days is still 30 calendar days")
    }

    /// A run inside a single day reads as 1 day, not 0 — "in 0 days" is nonsense.
    func testASameDayRunSpansOneDay() {
        let streak = CompletionStreak.Streak(completions: (1...3).map { _ in completion(daysAgo: 0) })
        XCTAssertEqual(streak.spanInDays, 1)
    }

    /// Comments with no timestamps still summarise, just without the span.
    func testUndatedCompletionsStillSummarise() {
        let undated = Comment(id: "x", content: "marked this as complete", type: .TEXT,
                              authorId: nil, author: nil, taskId: "t1",
                              createdAt: nil, updatedAt: nil)
        let streak = CompletionStreak.Streak(completions: [undated, undated, undated])
        XCTAssertNil(streak.spanInDays)
        let summary = CompletionStreak.summary(for: streak)
        XCTAssertTrue(summary.contains("3"))
        XCTAssertFalse(summary.hasPrefix("comments.streak"), "unresolved key: \(summary)")
    }
}
