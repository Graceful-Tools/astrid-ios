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

    // Retired: priority and assignee had their own row, restating what the
    // leading control already depicts. Named so their absence is checkable.
    case priority
    case assignee
}

enum MacTaskFields {

    /// The rows, in order. `showsTitle` is false for the board's inline card
    /// editor, which already draws the title on the card face.
    static func rows(showsTitle: Bool) -> [MacTaskFieldRow] {
        (showsTitle ? [.title] : []) + [.when, .lists, .description]
    }

    /// Every field the editor shows is one the user can change. The Lists row
    /// used to fail this: it drew chips from the task and a dash when empty,
    /// with no control attached — which is what "list selecting isn't working"
    /// turned out to mean.
    static func isEditable(_ row: MacTaskFieldRow) -> Bool {
        switch row {
        case .title, .when, .lists, .description: return true
        case .priority, .assignee: return false   // not rows at all any more
        }
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
    case complete
}

enum MacLeadingPicker {
    static var sections: [MacLeadingPickerSection] { [.priority, .assignee, .complete] }
}
#endif
