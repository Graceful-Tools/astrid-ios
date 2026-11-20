//  MarkDoneQuickSetRow.swift
//  The quick changer's completion row: "✓ Mark as done", or "✓ Mark as to-do" (ADEV-146).
//
//  Every quick changer (the board card's, the list row's and the task detail's, on the phone
//  and the Mac) used to end in a big accent-coloured "Complete task" button. Jon asked for it
//  back the way iOS used to draw it, which is also how web draws it since astrid-web #918:
//  a check mark on the left and the action written out beside it, not a button that shouts.
//  One view, so the four popovers cannot drift apart again.
//
//  The words are web's (`tasks.markAsDone` / `tasks.markAsTodo`), translated the same way in
//  all twelve languages.

import SwiftUI

/// What the row says and draws, with no SwiftUI in it, so a test can ask.
enum MarkDoneQuickSet {
    /// The label key: what tapping does, said from where the task is now.
    static func labelKey(completed: Bool) -> String {
        completed ? "tasks.mark_as_todo" : "tasks.mark_as_done"
    }

    static func label(completed: Bool) -> String {
        NSLocalizedString(labelKey(completed: completed), comment: "")
    }

    /// The same check mark both ways: muted once the task is done, so "to-do" does not read
    /// as a second "done".
    static let systemImage = "checkmark"
}

struct MarkDoneQuickSetRow: View {
    let completed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacing12) {
                Image(systemName: MarkDoneQuickSet.systemImage)
                    .fontWeight(.semibold)
                    .foregroundStyle(completed ? Theme.textMuted : Theme.accentInk)
                    .accessibilityHidden(true)
                Text(MarkDoneQuickSet.label(completed: completed))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .font(Theme.Typography.body())
            .padding(.vertical, Theme.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("taskOptions.complete")
    }
}
