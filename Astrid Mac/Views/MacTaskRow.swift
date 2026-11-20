//  MacTaskRow.swift
//  Astrid for Mac — iOS-style task row for the list view (replaces the flat Table).
//  Mirrors iOS `TaskRowView`: a priority-colored completion checkbox, the title (strikethrough
//  when done), and a metadata line with the due date + list chips. Priority is conveyed by the
//  checkbox ring, so there is NO separate priority column. Supports inline rename in place.

#if os(macOS)
import SwiftUI
import AppKit

struct MacTaskRow: View {
    let task: Task
    /// List ids the surrounding view already conveys (the currently-viewed list) — filtered out
    /// of the chip set so the row doesn't repeat the list you're already looking at.
    var hiddenListIds: Set<String> = []
    let isEditing: Bool
    @Binding var editingTitle: String
    var indent: Int = 0                  // subtask nesting depth (0 = top level)
    var isSelected: Bool = false
    @State private var showingQuickChanger = false
    @State private var hovering = false  // Mac hover affordance (77225941)
    @State private var checkPop = false   // tap feedback on the checkbox (see below)
    let onToggle: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    /// Selection tap. Owned by the row's CONTENT rather than the whole row so it cannot swallow
    /// the checkbox's click — a row-level `.onTapGesture` did exactly that, leaving the checkbox
    /// dead (task 652edb22).
    var onSelect: () -> Void = {}
    /// Trailing inset of the card. Drops to 0 while the detail pop-out is open so the row's edge
    /// MEETS the pop-out's arrow instead of stopping short of it (task 89e42f29).
    var trailingInset: CGFloat = 8
    /// Fired when this row actually starts a drag. The list needs to know WHICH task is in
    /// flight to decide whether to offer the promote-to-top-level target (task 2ed0d0de);
    /// `.onDrag` is the only moment that is knowable.
    var onDragBegan: () -> Void = {}

    @ObservedObject private var listService = ListService.shared
    @ObservedObject private var auth = AuthManager.shared

    /// The assignee to surface as an avatar (task.assignee, or a minimal User from the id so the
    /// shared UserImageCache can still resolve a picture) — nil for own/unassigned tasks.
    /// A small outlined label beside the title: won't-do (AITD-496), sync state (AITD-491).
    private func titleChip(_ labelKey: String, identifier: String) -> some View {
        titleChip(verbatim: NSLocalizedString(labelKey, comment: ""), identifier: identifier)
    }

    private func titleChip(verbatim label: String, identifier: String) -> some View {
        Text(verbatim: label)
            .macFont(MacTypography.rowMeta)
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.textMuted.opacity(0.5), lineWidth: 1))
            .accessibilityIdentifier(identifier)
    }

    /// Your own task's box completes, which is what a checkbox means when the task is not on a
    /// board; someone else's or nobody's opens the quick changer (AITD-375/382).
    ///
    /// Asked of the SHARED rule, not spelled here: the board card answers this differently
    /// (it always picks a status), and a row that writes its own copy of the question is how
    /// the two surfaces drift (task f9d7ed42).
    private var opensQuickChanger: Bool {
        TaskLeadingControl.action(surface: .listRow,
                                  assigneeId: task.assigneeId,
                                  currentUserId: auth.userId,
                                  completed: task.completed) == .openPicker
    }

    /// One decision for all three faces, so the rule is not written once per branch.
    private func handleLeadingTap() {
        if opensQuickChanger { showingQuickChanger = true; return }
        if ReducedMotion.allowsPop() { checkPop = true }   // no pop under Reduce Motion (AITD-624)
        onToggle()
    }

    private var avatarAssignee: User? {
        guard MacAssignee.showsAvatar(assigneeId: task.assigneeId, currentUserId: auth.userId,
                                      completed: task.completed),
              task.assigneeId != nil else { return nil }
        // Not `task.assignee ?? …`: a reassignment leaves that stale, which drew the previous
        // person on the row (AITD-442).
        return AssigneeResolver.resolve(task: task)
    }

    private var chipLists: [TaskList] {
        // Which lists get a chip is astrid-core's `listChips`, the rule iOS's row asks
        // (`chipListsForTaskRow`, AITD-622): board columns never draw as places. The Mac kept its
        // own filter until the design review (ADEV-60). The lists come from `listsById` — O(1),
        // and fresher than the task's embedded copy (Task 4e0ce183).
        chipListsForTaskRow((task.listIds ?? []).compactMap { listService.listsById[$0] },
                            hiddenListIds: hiddenListIds)
    }

    private var dueText: String? {
        // Shared with iOS (AITD-317) and with the board card (AITD-520). This used to format an
        // all-day date — stored at midnight UTC — in the user's own zone, so a 25 December task
        // printed as the 24th west of UTC.
        MacDueText.text(for: task.dueDateTime, isAllDay: task.isAllDay)
    }

    var body: some View {
        HStack(alignment: .center, spacing: MacRowHitArea.columnSpacing) {
            // The checkbox COLUMN, not just the glyph: a transparent layer behind it takes the
            // clicks that land in the padding around the checkbox and selects the row, instead of
            // leaving a dead strip down the left of every row (b556c6a9). The glyph sits on top and
            // keeps its own gesture, so completing a task is untouched (652edb22).
            ZStack(alignment: .leading) {
                if !isEditing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect() }
                }
            Group {
            if let assignee = avatarAssignee {
                // Assigned to someone else → show their avatar in place of the checkbox (iOS parity).
                MacAssigneeAvatar(user: assignee, priority: task.priority, size: MacTaskVisuals.rowCheckboxSize,
                                  repeating: MacCheckboxAsset.isRepeating(task.repeating))
                    .assigneeOverflowBadge(for: task, avatarSize: MacTaskVisuals.rowCheckboxSize)
                    // Someone else's face opens the quick changer (AITD-375).
                    .contentShape(Rectangle())
                    .onTapGesture { handleLeadingTap() }
            } else if TaskLeadingControl.kind(assigneeId: task.assigneeId,
                                              currentUserId: AuthManager.shared.userId,
                                              completed: task.completed) == .unassigned {
                // Nobody assigned → "U", not the checkbox (42013da7). Same three-state rule as
                // iOS, from the same shared helper, so a task cannot look different per platform.
                // Clicking still completes: the mark changes, the action does not. A tap gesture
                // rather than a Button for the same reason as the checkbox below.
                MacUnassignedMark(priority: task.priority, size: MacTaskVisuals.rowCheckboxSize,
                                  repeating: MacCheckboxAsset.isRepeating(task.repeating))
                    .strikethrough(task.completed)
                    .opacity(task.completed ? 0.5 : 1)
                    .scaleEffect(ReducedMotion.popScale(checkPop))
                    .animation(MacMotion.spring, value: checkPop)
                    .contentShape(Rectangle())
                    .onTapGesture { handleLeadingTap() }
                    .accessibilityLabel(Text(NSLocalizedString("assignee.unassigned", comment: "")))
            } else {
                // A `Button` here NEVER fires: inside a macOS `List` row the cell's own click
                // handling swallows it, so the checkbox was dead (task 652edb22). Gestures DO
                // receive clicks in these rows (row selection has always worked), so the checkbox
                // is a tap gesture that keeps full button semantics for VoiceOver and UI tests.
                // The check's own transition rarely plays: completing RE-SORTS the list, so the row
                // is replaced rather than updated in place and the animation never runs. A local
                // scale "pop" fires on the tap itself, so the click always gets visible feedback.
                MacTaskCheckbox(completed: task.completed, priority: task.priority,
                                size: MacTaskVisuals.rowCheckboxSize,
                                repeating: MacCheckboxAsset.isRepeating(task.repeating))
                    .scaleEffect(ReducedMotion.popScale(checkPop))
                    .animation(MacMotion.spring, value: checkPop)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleLeadingTap()
                        DispatchQueue.main.asyncAfter(deadline: .now() + MacMotion.fastDuration) {
                            checkPop = false
                        }
                    }
                    .macPointingHand()
                    .help(MarkDoneQuickSet.label(completed: task.completed))  // ADEV-146: the quick changer's words
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(task.completed ? NSLocalizedString("mac.a11y_completed_toggle", comment: "")
                                                      : NSLocalizedString("mac.a11y_not_completed_toggle", comment: ""))
                    .accessibilityAction { onToggle() }
                    // The state, for the UI suite — the label above is localized (AITD-526).
                    .accessibilityIdentifier(task.completed ? "taskRow.checkbox.completed" : "taskRow.checkbox.open")
            }
            }
            // Pinned where the add bar's checkbox sits, not centred in the column (AITD-508).
            .padding(.leading, MacRowHitArea.checkboxGlyphLeading(glyph: MacTaskVisuals.rowCheckboxSize))
            }
            // The SAME quick changer the detail panel and the board card show, so "same
            // behavior" is one view rather than three that have to agree (task 132d7b3f).
            .popover(isPresented: $showingQuickChanger, arrowEdge: .bottom) {
                MacQuickChanger(task: task, onDismiss: { showingQuickChanger = false })
            }
            .frame(width: MacRowHitArea.checkboxColumnWidth(glyph: MacTaskVisuals.rowCheckboxSize),
                   alignment: .leading)
            .padding(.vertical, MacRowHitArea.verticalPadding)

            let content = VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField(NSLocalizedString("mac.title", comment: ""), text: $editingTitle)
                        .textFieldStyle(.plain)
                        .macFont(MacTypography.rowTitle)
                        .macTextSelection()
                        .onSubmit(onCommitEdit)
                        .onExitCommand(perform: onCancelEdit)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(task.title)
                            .macFont(MacTypography.rowTitle)
                            .strikethrough(task.completed)
                            .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                            .lineLimit(2)
                        // Closed as won't-do reads differently from done (AITD-496), as on iOS and web.
                        if ClosedReason.isCanceled(task) {
                            titleChip(ClosedReason.chipLabelKey, identifier: "taskRow.wontDoChip")
                        }
                        // Made on a GitHub board and not all written there yet (AITD-491).
                        if let mark = TaskSyncState.mark(for: task) {
                            titleChip(TaskSyncState.chipLabelKey(for: mark), identifier: "taskRow.syncChip")
                        }
                        // The GitHub issue a task on a GitHub board is, `repo#N`; opens it (AITD-491).
                        if let label = task.remote?.chipLabel, let url = task.remote?.pageURL {
                            Link(destination: url) { titleChip(verbatim: label, identifier: "taskRow.remoteChip") }
                        }
                    }
                }

                let chips = chipLists   // computed ONCE per row render (was 3 references = 3 computations)
                // The board column as a coloured pill (AITD-613); this row is never a board card.
                let boardStatus = TaskBoardStatus.of(task, lists: listService.lists,
                                                     projects: ProjectService.shared.projects)
                if dueText != nil || !chips.isEmpty || boardStatus != nil {
                    HStack(spacing: 8) {
                        if let dueText {
                            Text(dueText)
                                .macFont(MacTypography.rowMeta)
                                .foregroundStyle(Theme.textMuted)
                        }
                        if let boardStatus {
                            TaskBoardStatusPill(status: boardStatus)
                                .macFont(MacTypography.rowMeta)
                        }
                        ForEach(chips.prefix(2)) { list in
                            HStack(spacing: 4) {
                                MacListIcon(list: list, size: 11)
                                Text(list.name).macFont(MacTypography.rowMeta).lineLimit(1)
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.bgSecondary, in: Capsule())
                        }
                        if chips.count > 2 {
                            Text("+\(chips.count - 2)")
                                .macFont(MacTypography.rowMeta)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            // The tappable selection area is the content + trailing space — everything except the
            // checkbox/avatar, which keep their own hit target.
            HStack(spacing: 0) {
                content
                Spacer(minLength: 0)
            }
            .padding(.vertical, MacRowHitArea.verticalPadding)
            .padding(.trailing, MacRowHitArea.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // While the title is being edited the row must stay OUT of the way: a drag region over
            // a TextField turns "drag to select text" into a row drag, so text could not be
            // selected with the mouse (task 6a7aaf55). Tap-to-select is likewise suppressed so a
            // click inside the field places the caret instead of re-selecting the row.
            .modifier(MacRowInteractions(enabled: !isEditing, dragId: task.id,
                                         isSelected: isSelected, onSelect: onSelect,
                                         onDragBegan: onDragBegan))
        }
        // A floor so a title-only task stands as tall as one carrying a date or a list chip —
        // without it height followed content and a mixed list read as a ragged column
        // (Task 7c5cd097). Applied to the card, so the whole surface grows: the two columns'
        // hit areas already fill it, and a taller card means a taller click target.
        .frame(minHeight: MacRowHitArea.minRowHeight)
        // No outer padding: both columns carry it inside their own hit areas (b556c6a9).
        // Themed card so the row surface reflects the theme (Ocean = light card on cyan, Dark = raised
        // card on dark). Selection is a SUBTLE thin accent (b8d1ec16); hover a lighter wash (77225941).
        .background(MacSelectionStyle.fill(isSelected: isSelected, hovering: hovering),
                    in: RoundedRectangle(cornerRadius: AstridTokens.Layout.Compact.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: AstridTokens.Layout.Compact.rowRadius)
            .stroke(MacSelectionStyle.borderColor(isSelected: isSelected, hovering: hovering),
                    lineWidth: MacSelectionStyle.borderWidth(isSelected: isSelected)))
        .onHover { h in withAnimation(ReducedMotion.hover) { hovering = h } }
        .padding(.leading, 8 + MacRowHitArea.indent(level: indent))   // per-level indent, capped at 4
        .padding(.trailing, trailingInset)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// Row tap-to-select + drag-to-move, applied only when the row is NOT in inline-edit mode.
/// Drag regions swallow clicks and text-selection drags for everything inside them, so they must
/// never cover an active text field (tasks 652edb22 / 6a7aaf55).
struct MacRowInteractions: ViewModifier {
    let enabled: Bool
    let dragId: String
    let isSelected: Bool
    let onSelect: () -> Void
    var onDragBegan: () -> Void = {}

    func body(content: Content) -> some View {
        if enabled {
            // `.onDrag`, not `.draggable`: `.draggable` claimed the first mouse-down as a possible
            // drag and swallowed the click, so opening a task took two or three attempts. Gating
            // it on `isSelected` fixed the click but meant an UNSELECTED row could not be dragged
            // at all — which is why drag-and-drop read as missing (task 83f45d49). `.onDrag` only
            // begins once the pointer moves past a threshold, so a click and a drag coexist.
            content
                .highPriorityGesture(TapGesture().onEnded { onSelect() })
                .onDrag {
                    onDragBegan()
                    return NSItemProvider(object: dragId as NSString)
                }
        } else {
            content
        }
    }
}
#endif
