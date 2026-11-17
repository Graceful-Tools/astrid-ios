import AstridCore
import Foundation

//  The task row's and task detail's layout rules, asked of astrid-core's rule door (core
//  2b50348, AWTD2-216; AITD-622). Each of these was a Swift copy of a function the core already
//  had; what is left here is the app's names for the answers and a safe fallback for when the
//  core cannot answer.

/// A field in the task detail, named so the ORDER can be stated once (task c8a1ff51).
enum TaskDetailField: Equatable {
    case assignee      // "Who"
    case when          // "Date"
    case priority
    case lists

    /// astrid-core's name for the field (`rows::detail::Field::name`).
    init?(coreName: String) {
        switch coreName {
        case "assignee": self = .assignee
        case "when": self = .when
        case "priority": self = .priority
        case "lists": self = .lists
        default: return nil
        }
    }
}

/// The order the task detail shows its fields in, under the title.
///
/// Jon: "Order (under task title) — Who, Date, Priority, Lists. Implement same order on all
/// interfaces for list mode (iOS, Mac, web — board details, mobile etc)." The ask is CONTINUITY,
/// so the order is astrid-core's (`detailLayout`, `rows::detail::field_order`; AWTD2-216,
/// AITD-622) — the same answer web and Windows read — rather than a Swift copy of it.
enum TaskDetailFieldOrder {

    /// List mode, top to bottom, under the title.
    static var listMode: [TaskDetailField] {
        let order = CoreRules.detailLayout(displayMode: CoreTaskLayout.wireValue,
                                           isInProject: false, isReadOnly: false)?
            .fieldOrder.compactMap(TaskDetailField.init(coreName:))
        // A detail with no fields cannot be edited at all; if the core could not answer, every
        // field still appears, in the contract's order.
        guard let order, !order.isEmpty else { return [.assignee, .when, .priority, .lists] }
        return order
    }
}

/// Whether task details show a BOARD STATE row (AITD-327 on the Mac, AITD-332 on iOS, both
/// layouts since AITD-555).
///
/// The row is for a task that is ON a board — there the column is real information the list
/// layout was hiding — and never for a read-only viewer, because the row is a mover whose chips
/// write. Asked of astrid-core (`detailLayout`, `rows::detail::shows_board_state`; AWTD2-216,
/// AITD-622), so the phone, the Mac and web cannot drift into three answers.
enum TaskDetailProjectStateRow {

    /// - Parameters:
    ///   - isInProject: whether the task has a board column at all — ask `isTaskInProject`, never
    ///     a condition written at the call site.
    ///   - isReadOnly: the public-list viewer.
    static func isVisible(isInProject: Bool,
                          isReadOnly: Bool) -> Bool {
        // A failed answer hides the row: a mover drawn where it must not be can write.
        CoreRules.detailLayout(displayMode: CoreTaskLayout.wireValue, isInProject: isInProject,
                               isReadOnly: isReadOnly)?.showsBoardState ?? false
    }
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

/// The lists worth surfacing as chips on a task row: board columns (status lists) removed, and
/// `hiddenListIds` — the lists the surrounding view already conveys — removed too. In the LIST
/// view that is the list being viewed; on a BOARD, the project's domain list and the current
/// column. Order is the task's own.
///
/// Asked of astrid-core (`listChips`, `rows::list_chips`; AWTD2-216, AITD-622), the same filter
/// every core-drawn row applies, so a chip cannot appear on the phone and not on web.
func chipListsForTaskRow(_ lists: [TaskList]?,
                         hiddenListIds: Set<String> = []) -> [TaskList] {
    guard let lists, !lists.isEmpty else { return [] }
    let input = lists.map { ChipListInput(id: $0.id, name: $0.name, listType: $0.listType) }
    // A failed answer draws no chips: a missing chip is quieter than a column drawn as a place.
    guard let ids = CoreRules.listChipIds(lists: input, hiddenListIds: hiddenListIds) else { return [] }
    let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return ids.compactMap { byId[$0] }
}
