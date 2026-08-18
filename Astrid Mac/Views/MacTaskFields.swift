//  MacTaskFields.swift
//  Astrid for Mac — which fields a task's editor shows, and what a list pick means.
//
//  Stated as data, apart from the view, for the usual reason: "the board renders
//  the detail's fields" is a claim a test can hold, whereas a second SwiftUI
//  body that happens to look similar is not.

#if os(macOS)
import CoreGraphics
import Foundation

/// A row in the task's field block.
enum MacTaskFieldRow: Equatable {
    case title
    case when
    case lists
    case description

    /// Rows only in LIST mode. In project mode the leading control depicts both, so a row
    /// restating them spends panel width saying it twice (task 42013da7).
    case priority
    case assignee

    /// The Mac's name for a shared field, so `MacTaskFields.rows` can build list mode straight
    /// from `TaskDetailFieldOrder.listMode` (task c8a1ff51).
    init(_ field: TaskDetailField) {
        switch field {
        case .assignee: self = .assignee
        case .when:     self = .when
        case .priority: self = .priority
        case .lists:    self = .lists
        }
    }
}

enum MacTaskFields {

    /// The rows, in order. `showsTitle` is false for the board's inline card
    /// editor, which already draws the title on the card face.
    ///
    /// `displayMode` decides whether priority and assignee are rows here or stay behind the
    /// leading control (task 729a190e). It is required rather than defaulted: the whole bug
    /// was that this choice had one hardcoded answer, and a default would let a new call site
    /// re-hardcode it without anyone noticing.
    ///
    /// In LIST mode the order comes from `TaskDetailFieldOrder.listMode` — Who, Date, Priority,
    /// Lists — because the ask was CONTINUITY across the phone, the Mac and web (task c8a1ff51).
    /// This used to be `[.priority, .assignee] + [.when, .lists]`, and iOS independently used
    /// the same wrong order: the same mistake twice, which is what two views deciding for
    /// themselves produces. Derived rather than restated, so a change to the shared list
    /// reaches the Mac without anyone remembering to come here.
    static func rows(showsTitle: Bool, displayMode: TaskDisplayMode) -> [MacTaskFieldRow] {
        let leading: [MacTaskFieldRow] = showsTitle ? [.title] : []
        guard displayMode.showsSeparateAssigneeAndPriorityRows else {
            // Project mode: priority and assignee are not rows at all — the leading control
            // depicts both (task 42013da7) — so there is no order to share.
            return leading + [.when, .lists, .description]
        }
        return leading + TaskDetailFieldOrder.listMode.map(MacTaskFieldRow.init) + [.description]
    }

    /// Every field the editor shows is one the user can change. The Lists row
    /// used to fail this: it drew chips from the task and a dash when empty,
    /// with no control attached — which is what "list selecting isn't working"
    /// turned out to mean.
    static func isEditable(_ row: MacTaskFieldRow) -> Bool {
        // Every row, without exception. Priority and assignee used to return false here
        // because they were not rows at all; now that list mode shows them, a false would
        // ship exactly the read-only row the Lists bug was about.
        true
    }

    /// Picking a list toggles the task's membership of it. Multi-select: a task
    /// can live in several lists, and leaving every one of them (My Tasks only)
    /// is a legal state.
    ///
    /// Order is preserved on add so the chips don't reshuffle when you add one.
    static func toggling(listId: String, in current: [String]) -> [String] {
        current.contains(listId) ? current.filter { $0 != listId } : current + [listId]
    }

    /// What the description row shows when it is not being edited.
    ///
    /// A description of only whitespace is not a description — it has to fall
    /// back to the prompt, or the row renders as a blank clickable gap with
    /// nothing telling you what it is.
    enum DescriptionDisplay: Equatable {
        case body(String)
        case placeholder
    }

    static func descriptionDisplay(_ text: String) -> DescriptionDisplay {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .placeholder : .body(text)
    }

    /// Gap between the chips on the When row.
    ///
    /// Was 10, which read as a gulf between the date and the time and cost the
    /// row width it did not have — enough to push a chip onto a second line that
    /// would otherwise have fitted.
    static var chipSpacing: CGFloat { 5 }

    /// How tightly the fields are packed. A board card is a ~250pt column; the
    /// detail is a 380pt panel. One view, two densities — not two views.
    enum Density {
        case detail
        case boardCard

        var rowSpacing: CGFloat {
            switch self {
            case .detail: return 10
            case .boardCard: return 6
            }
        }

        var padding: CGFloat {
            switch self {
            case .detail: return 0      // the Form supplies its own
            case .boardCard: return 10
            }
        }
    }
}

/// What the popover behind the leading control offers.
///
/// The leading control already depicts priority (its colour) and assignee (its
/// photo), so those are the two things it should let you set — plus completing
/// the task, which is what the control does when you click it on a row. iOS
/// reached this conclusion first (42013da7); this is the Mac inheriting it.
enum MacLeadingPickerSection: Equatable {
    case priority
    case assignee
    /// The task's board column — Ready / Doing / Waiting, stored as `statusRole`.
    case projectState
    case complete
}

enum MacLeadingPicker {

    /// What the popover behind the leading control offers.
    ///
    /// Project mode gets board state as well (task 729a190e): in that mode the control is the
    /// quick changer, and moving a task between columns is the thing you do most. List mode
    /// does not — priority and assignee are rows of their own there, and a board column is a
    /// project idea. Offering both everywhere would rebuild the hybrid layout this setting
    /// exists to end.
    ///
    /// A BOARD CARD gets it in both modes (task f9d7ed42). List mode's omission is an argument
    /// about the DETAIL panel's layout — a board column is a project idea, and a row for it in
    /// the list layout rebuilds the hybrid. On a board that argument does not apply: the card is
    /// already in a board, its column is the one thing on screen that is about to change, and
    /// without this section the control offers no way to change it.
    static func sections(for displayMode: TaskDisplayMode,
                         surface: TaskLeadingControlSurface = .detail) -> [MacLeadingPickerSection] {
        let showsProjectState = displayMode.usesCompactTaskDetail || surface == .boardCard
        return showsProjectState
            ? [.priority, .assignee, .projectState, .complete]
            : [.priority, .assignee, .complete]
    }
}
#endif
