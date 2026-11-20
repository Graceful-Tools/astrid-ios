//  MarkDoneQuickSetRow.swift
//  The quick changer's completion row: "✓ Mark as done", or "✓ Mark as to-do" (ADEV-146).
//
//  Every quick changer (the board card's, the list row's and the task detail's, on the phone
//  and the Mac) used to end in a big accent-coloured "Complete task" button. Jon asked for it
//  back the way iOS used to draw it, which is also how web draws it since astrid-web #918:
//  a check mark on the left and the action written out beside it, not a button that shouts.
//  ADEV-148 made that mark the task row's own checkbox: unchecked, or checked once done.
//  One view, so the four popovers cannot drift apart again.
//
//  The words are web's (`tasks.markAsDone` / `tasks.markAsTodo`), translated the same way in
//  all twelve languages.
//
//  ADEV-152: the checkbox is the task row's full size, the row sits on the assignee row's surface
//  so it stands out from the popover, and its ink comes from the theme's palette (the iOS
//  `Theme` text colour is the light ink in every theme, which drew dark-on-dark). A task that is
//  not yours no longer swaps the row for a "Complete this task?" block: it is the same row with
//  one muted line saying whose it is, and tapping the row is the confirmation (ADEV-70, ADEV-79).

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

    /// The task row's own checkbox (ADEV-148): unchecked beside "Mark as done", checked beside
    /// "Mark as to-do", in the task's priority colour, so the row looks like the task itself.
    static func checkboxAssetName(completed: Bool, priority: Int, repeating: Bool) -> String {
        TaskCheckboxAsset.name(priority: priority, completed: completed, repeating: repeating)
    }

    /// The task row's own checkbox size (ADEV-152: "full size as in rows").
    #if os(macOS)
    static let checkboxSize = AstridTokens.Size.Compact.leadingControlDetail
    #else
    static let checkboxSize = AstridTokens.Size.Comfortable.leadingControl
    #endif

    /// The line under the label for a task that is not yours: "Assigned to Ada" or "Not assigned
    /// to anyone", so the tap is never a blind one (ADEV-70). Nil for your own task.
    static func note(needsConfirmation: Bool, assigneeLabel: String?) -> String? {
        needsConfirmation ? CompletionConfirmation.message(assigneeLabel: assigneeLabel) : nil
    }
}

struct MarkDoneQuickSetRow: View {
    let completed: Bool
    let priority: Int
    let repeating: Bool
    /// Whose task it is, when it is not yours — `MarkDoneQuickSet.note`.
    var note: String? = nil
    let action: () -> Void

    @ThemedPalette private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacing12) {
                Image(MarkDoneQuickSet.checkboxAssetName(completed: completed, priority: priority,
                                                         repeating: repeating))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: MarkDoneQuickSet.checkboxSize, height: MarkDoneQuickSet.checkboxSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AstridTokens.Space.s2) {
                    Text(MarkDoneQuickSet.label(completed: completed))
                        .font(Theme.Typography.body())
                        .foregroundStyle(palette.textPrimary)
                    if let note {
                        Text(note)
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.spacing8)
            .padding(.horizontal, Theme.spacing12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("taskOptions.complete")
    }
}
