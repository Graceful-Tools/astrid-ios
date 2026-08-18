import Foundation

/// A field in the task detail, named so the ORDER can be stated once (task c8a1ff51).
enum TaskDetailField: Equatable {
    case assignee      // "Who"
    case when          // "Date"
    case priority
    case lists
}

/// The order the task detail shows its fields in, under the title.
///
/// Jon: "Order (under task title) — Who, Date, Priority, Lists. Implement same order on all
/// interfaces for list mode (iOS, Mac, web — board details, mobile etc)."
///
/// It lives here rather than in either platform's view because the ask is CONTINUITY: the point
/// is that the phone, the Mac and the web agree. Both platforms put Priority first and Who
/// second before this — the same wrong order twice, which is what happens when two views each
/// decide for themselves.
///
/// PROJECT mode is deliberately not covered. There, priority and assignee live behind the
/// leading control and are not rows at all (task 729a190e), so there is no order to state.
enum TaskDetailFieldOrder {

    /// List mode, top to bottom, under the title.
    static let listMode: [TaskDetailField] = [.assignee, .when, .priority, .lists]
}

/// The marks that stand for a task's priority.
///
/// One definition, because the "!"/"!!"/"!!!" convention was written out in half a dozen places
/// — the Mac's visuals, the iOS list's sort keys, quick add, the foundation-model prompt — and a
/// convention spelled six times is one that drifts.
enum PriorityGlyph {

    /// The mark that IDENTIFIES the priority row: "!!!", not a flag (task c8a1ff51). The flag
    /// said "some field about importance"; the marks are the vocabulary the app already uses
    /// for priority everywhere else, so the row is recognisable without reading the label.
    static let rowIcon = "!!!"

    /// The mark for one priority.
    static func symbol(_ priority: Task.Priority) -> String {
        switch priority {
        case .none: return "○"
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }
}
