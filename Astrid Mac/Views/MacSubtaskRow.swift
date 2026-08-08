//  MacSubtaskRow.swift
//  Astrid for Mac — metrics for a subtask row, and for the row that adds one.
//
//  The subtask list used a green `checkmark.circle.fill` / `circle` SF Symbol —
//  the one checkbox in the app that did not use the app's own checkbox artwork,
//  so a subtask looked like it belonged to a different program. And the "add"
//  row was a labelled text field plus an Add button, lining up with neither the
//  rows above it nor anything else in the panel.
//
//  Both now use the same checkbox and the same column, so the add row reads as
//  the next subtask rather than as a form control.

#if os(macOS)
import CoreGraphics
import Foundation

enum MacSubtaskRow {
    /// Subtask checkboxes are row-sized, not detail-sized: they are a list
    /// inside the panel, not the panel's own title control.
    static var checkboxSize: CGFloat { MacTaskVisuals.rowCheckboxSize }

    /// Gap between the checkbox and the title. Shared by the subtask rows and
    /// the add row, which is what puts their text on one left edge.
    static var checkboxGap: CGFloat { 8 }

    /// The add row's checkbox is a PROMPT, not a control — it shows the shape a
    /// new subtask will take. Faded so it doesn't read as a task you can tick.
    static var placeholderOpacity: CGFloat { 0.35 }

    /// The shape that placeholder takes: the list's default priority, so the
    /// prompt shows the checkbox the new subtask will actually get. Falls back
    /// to the parent's own priority, then to none.
    static func placeholderPriority(for task: Task,
                                    lists: [String: TaskList]) -> Task.Priority {
        let listDefault = (task.listIds ?? [])
            .compactMap { lists[$0]?.defaultPriority }
            .first
        if let listDefault, let priority = Task.Priority(rawValue: listDefault) {
            return priority
        }
        return task.priority
    }
}
#endif

#if os(macOS)
/// Metrics for the description row.
///
/// It was a permanently-live TextEditor with a 70pt floor: an empty task showed
/// an editing box with a scrollbar, and a long description scrolled inside that
/// window instead of taking the room the panel had.
enum MacDescriptionRow {
    /// Floor for the editor once open — a click should land you in something
    /// with room to type, not a single line.
    static var minEditorHeight: CGFloat { 56 }
}
#endif
