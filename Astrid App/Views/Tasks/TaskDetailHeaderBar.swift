//  TaskDetailHeaderBar.swift
//  The bar across the top of task details — back, the title, full screen, and the actions menu.
//
//  Extracted from `TaskDetailViewNew` (AITD-425) for the same reason `TaskDetailLeadingControl`
//  was (AITD-363): that file is the largest in the repo, the source-file ratchet asked whether
//  it should still be one file, and the header is the most self-contained thing in it — four
//  controls with no state of their own beyond what the parent already owns.
//
//  A custom bar rather than a toolbar because iOS 26 draws toolbar items as glass bubbles.
//
//  What each control DOES is not decided here. `TaskDetailHeader` in `Core/Layout/` owns the
//  back action and the identifiers, so the panel and the pushed presentations cannot answer
//  "what does back mean" two different ways.

import SwiftUI

struct TaskDetailHeaderBar: View {
    let isReadOnly: Bool
    /// Supplied only by the iPad side panel, where it clears `selectedTask`. Its presence is
    /// what tells `TaskDetailHeader.backAction` which presentation this is.
    let onClose: (() -> Void)?
    let isFullScreen: Bool
    let onToggleFullScreen: (() -> Void)?
    let scrollToTopAction: (() -> Void)?
    let background: Color
    @Binding var showingCopySheet: Bool
    @Binding var showingShareSheet: Bool
    @Binding var showingDeleteConfirmation: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color {
        colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary
    }

    var body: some View {
        HStack {
            backButton

            Spacer()

            Button {
                scrollToTopAction?()
            } label: {
                Text(NSLocalizedString("tasks.task_details", comment: ""))
                    .font(.headline)
                    .foregroundColor(foreground)
            }
            .buttonStyle(.plain)
            // How a UI test knows the detail is open (task b86c97c5). The suite matched
            // `app.staticTexts["Task Details"]`, which never could: the header is a
            // BUTTON — it scrolls the panel to the top — so the label belongs to the
            // button, not to a static text. Nine tests read that as "detail did not
            // appear" when it had. An identifier says which element rather than hoping
            // for a type, and it does not change when the app is in French.
            .accessibilityIdentifier(TaskDetailHeader.accessibilityIdentifier)

            Spacer()

            // Expand the panel / put it back (task c5ba07ed). Same affordance, glyphs and
            // strings as the Mac pop-out (42013da7) and the board's full screen — the
            // point is the same one: a description needs more room than a side panel.
            if let onToggleFullScreen {
                Button(action: onToggleFullScreen) {
                    Image(systemName: isFullScreen
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(foreground)
                        .accessibilityLabel(Text(NSLocalizedString(
                            isFullScreen ? "board.exit_full_screen" : "board.full_screen",
                            comment: "")))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("taskDetail.fullScreen")
                .padding(.trailing, 12)
            }

            if !isReadOnly {
                actionsMenu
            } else {
                // Spacer to balance the back button — the same box, or the title stops
                // being centred now that back carries a tap target (AITD-425).
                Color.clear
                    .frame(width: TaskDetailHeader.minimumTapTarget,
                           height: TaskDetailHeader.minimumTapTarget)
            }
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background(background)
    }

    private var backButton: some View {
        Button {
            // Which of the two this is lives in the shared helper, not here: the panel case
            // is the one where dismiss() silently does nothing, and it was only ever
            // established by reading the call sites (AITD-425).
            switch TaskDetailHeader.backAction(hasPanelClose: onClose != nil) {
            case .closePanel:   onClose?()
            case .dismissStack: dismiss()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(foreground)
                // The glyph is ~11×17pt, and .buttonStyle(.plain) makes the glyph the whole
                // hit area — so most taps missed (AITD-425). Same fix the "..." menu at the
                // other end of this bar already carries.
                .frame(minWidth: TaskDetailHeader.minimumTapTarget,
                       minHeight: TaskDetailHeader.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(TaskDetailHeader.backAccessibilityIdentifier)
        .accessibilityLabel(Text(NSLocalizedString("actions.back", comment: "")))
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                showingCopySheet = true
            } label: {
                Label(NSLocalizedString("tasks.copy_task", comment: ""), systemImage: "doc.on.doc")
            }

            Button {
                showingShareSheet = true
            } label: {
                Label(NSLocalizedString("tasks.share_task", comment: ""), systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(NSLocalizedString("tasks.delete_task", comment: ""), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20))
                .rotationEffect(.degrees(90))  // SF Symbols has no ellipsis.vertical — rotate the horizontal one to match the web's vertical three-dot
                .foregroundColor(foreground)
                .frame(minWidth: TaskDetailHeader.minimumTapTarget,
                       minHeight: TaskDetailHeader.minimumTapTarget)  // 44pt is Apple HIG min tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("taskDetailActionsMenu")
        .accessibilityLabel("Task actions")
    }
}
