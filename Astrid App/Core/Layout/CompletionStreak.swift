import Foundation

/// Folds a run of repeating-task completion comments into one streak row (Task dd3fda86).
///
/// A repeating task appends a system comment on every rollover, so a daily task buries its real
/// conversation under a month of identical lines. This collapses a run into "completed N times",
/// which the detail views expand back to the individual dates on tap.
///
/// Shared between iOS and Mac deliberately: both clients must agree on what counts as a streak,
/// and Web mirrors this rule (companion task 59e2dcff).
///
/// KNOWN FRAGILITY: the server writes these as prose — `lib/task-update-handler.ts` stores
/// `"<name> marked this as complete"` with `authorId: nil` and no type discriminator, so there is
/// nothing structural to key off. If that sentence is ever reworded or localised the fold stops
/// working silently. The durable fix is a typed field on the comment, filed on 59e2dcff.
enum CompletionStreak {

    /// The English marker the server writes. Lowercased comparison — the sentence is prefixed
    /// with the updater's name, which we do not control.
    static let marker = "marked this as complete"

    /// Below this a fold costs more than it saves: collapsing two lines into "completed 2 times"
    /// hides as much as it shows.
    static let minimumRun = 3

    /// One entry in a rendered comment list: either a real comment, or a folded run of them.
    enum Item: Equatable, Identifiable {
        case comment(Comment)
        case streak(Streak)

        var id: String {
            switch self {
            case .comment(let c): return c.stableId
            case .streak(let s):  return "streak:\(s.id)"
            }
        }
    }

    struct Streak: Equatable {
        /// The folded comments, oldest first — what the expanded view lists.
        let completions: [Comment]

        var id: String { completions.first?.stableId ?? "empty" }
        var count: Int { completions.count }

        var dates: [Date] { completions.compactMap(\.createdAt) }

        /// Days from the first completion in the run to the last, counted in CALENDAR days.
        ///
        /// Measured start-of-day to start-of-day on purpose. Completions land at whatever time of
        /// day the person happened to tick the box, and `dateComponents(.day)` truncates: a run
        /// from Jan 1 at 09:00 to Jan 31 at 08:00 is 29.96 days, which floors to 29 and reads as
        /// a day short. "In N days" means calendar days to a reader.
        ///
        /// A run inside one day reads as 1 day, not 0. Nil when the comments carry no timestamps.
        var spanInDays: Int? {
            guard let first = dates.min(), let last = dates.max() else { return nil }
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: first),
                                               to: calendar.startOfDay(for: last)).day ?? 0
            return max(1, days)
        }
    }

    /// Is this one of the completion lines a repeating task leaves behind?
    ///
    /// System comments only — `authorId == nil`. A comment someone actually wrote is never folded,
    /// even if they happen to type the same words.
    static func isCompletion(_ comment: Comment) -> Bool {
        guard comment.authorId == nil else { return false }
        return comment.content.lowercased().contains(marker)
    }

    /// Fold runs of consecutive completion comments, preserving order and everything else.
    ///
    /// Consecutive matters: a real comment in the middle of a run splits it, because the
    /// conversation around it is the thing worth keeping readable.
    static func fold(_ comments: [Comment], minimumRun: Int = minimumRun) -> [Item] {
        var items: [Item] = []
        var run: [Comment] = []

        func flushRun() {
            guard !run.isEmpty else { return }
            if run.count >= minimumRun {
                items.append(.streak(Streak(completions: run)))
            } else {
                items.append(contentsOf: run.map(Item.comment))
            }
            run = []
        }

        for comment in comments {
            if isCompletion(comment) {
                run.append(comment)
            } else {
                flushRun()
                items.append(.comment(comment))
            }
        }
        flushRun()
        return items
    }

    /// "Completed 6 times in 30 days", or without the span when the comments carry no dates.
    static func summary(for streak: Streak) -> String {
        if let days = streak.spanInDays {
            return String(format: NSLocalizedString("comments.streak_summary", comment: ""),
                          streak.count, days)
        }
        return String(format: NSLocalizedString("comments.streak_summary_no_span", comment: ""),
                      streak.count)
    }
}
