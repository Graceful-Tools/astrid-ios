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

    @ObservedObject private var listService = ListService.shared
    @ObservedObject private var auth = AuthManager.shared

    /// The assignee to surface as an avatar (task.assignee, or a minimal User from the id so the
    /// shared UserImageCache can still resolve a picture) — nil for own/unassigned tasks.
    private var avatarAssignee: User? {
        guard MacAssignee.showsAvatar(assigneeId: task.assigneeId, currentUserId: auth.userId),
              let id = task.assigneeId else { return nil }
        return task.assignee ?? User(id: id, email: nil, name: nil, image: nil)
    }

    private var chipLists: [TaskList] {
        // O(1) lookups via listsById (was an O(lists) scan per id, per reference — Task 4e0ce183).
        (task.listIds ?? [])
            .filter { !hiddenListIds.contains($0) }
            .compactMap { listService.listsById[$0] }
    }

    private var dueText: String? {
        guard let due = task.dueDateTime else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = task.isAllDay ? .none : .short
        return f.string(from: due)
    }

    var body: some View {
        HStack(alignment: .center, spacing: MacRowHitArea.columnSpacing) {
            // The checkbox COLUMN, not just the glyph: a transparent layer behind it takes the
            // clicks that land in the padding around the checkbox and selects the row, instead of
            // leaving a dead strip down the left of every row (b556c6a9). The glyph sits on top and
            // keeps its own gesture, so completing a task is untouched (652edb22).
            ZStack {
                if !isEditing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect() }
                }
            if let assignee = avatarAssignee {
                // Assigned to someone else → show their avatar in place of the checkbox (iOS parity).
                MacAssigneeAvatar(user: assignee, priority: task.priority, size: MacTaskVisuals.rowCheckboxSize)
            } else if TaskLeadingControl.kind(assigneeId: task.assigneeId,
                                              currentUserId: AuthManager.shared.userId) == .unassigned {
                // Nobody assigned → "U", not the checkbox (42013da7). Same three-state rule as
                // iOS, from the same shared helper, so a task cannot look different per platform.
                // Clicking still completes: the mark changes, the action does not. A tap gesture
                // rather than a Button for the same reason as the checkbox below.
                Text(TaskLeadingControl.unassignedGlyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTaskVisuals.priorityColor(task.priority))
                    .frame(width: MacTaskVisuals.rowCheckboxSize, height: MacTaskVisuals.rowCheckboxSize)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(MacTaskVisuals.priorityColor(task.priority), lineWidth: 1.5))
                    .strikethrough(task.completed)
                    .opacity(task.completed ? 0.5 : 1)
                    .scaleEffect(checkPop ? 1.28 : 1)
                    .animation(MacMotion.spring, value: checkPop)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        checkPop = true
                        onToggle()
                    }
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
                    .scaleEffect(checkPop ? 1.28 : 1)
                    .animation(MacMotion.spring, value: checkPop)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        checkPop = true
                        onToggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + MacMotion.fastDuration) {
                            checkPop = false
                        }
                    }
                    .macPointingHand()
                    .help(task.completed ? "Mark incomplete" : "Mark complete")
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(task.completed ? "Completed, mark incomplete" : "Not completed, mark complete")
                    .accessibilityAction { onToggle() }
            }
            }
            .frame(width: MacRowHitArea.checkboxColumnWidth(glyph: MacTaskVisuals.rowCheckboxSize),
                   alignment: .trailing)
            .padding(.vertical, MacRowHitArea.verticalPadding)

            let content = VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField(NSLocalizedString("mac.title", comment: ""), text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(MacTypography.rowTitle)
                        .onSubmit(onCommitEdit)
                        .onExitCommand(perform: onCancelEdit)
                } else {
                    Text(task.title)
                        .font(MacTypography.rowTitle)
                        .strikethrough(task.completed)
                        .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                        .lineLimit(2)
                }

                let chips = chipLists   // computed ONCE per row render (was 3 references = 3 computations)
                if dueText != nil || !chips.isEmpty {
                    HStack(spacing: 8) {
                        if let dueText {
                            Text(dueText)
                                .font(MacTypography.rowMeta)
                                .foregroundStyle(Theme.textMuted)
                        }
                        ForEach(chips.prefix(2)) { list in
                            HStack(spacing: 4) {
                                MacListIcon(list: list, size: 11)
                                Text(list.name).font(MacTypography.rowMeta).lineLimit(1)
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.bgSecondary, in: Capsule())
                        }
                        if chips.count > 2 {
                            Text("+\(chips.count - 2)")
                                .font(MacTypography.rowMeta)
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
                                         isSelected: isSelected, onSelect: onSelect))
        }
        // No outer padding: both columns carry it inside their own hit areas (b556c6a9).
        // Themed card so the row surface reflects the theme (Ocean = light card on cyan, Dark = raised
        // card on dark). Selection is a SUBTLE thin accent (b8d1ec16); hover a lighter wash (77225941).
        .background(MacSelectionStyle.fill(isSelected: isSelected, hovering: hovering),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(MacSelectionStyle.borderColor(isSelected: isSelected, hovering: hovering),
                    lineWidth: MacSelectionStyle.borderWidth(isSelected: isSelected)))
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
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

    func body(content: Content) -> some View {
        if enabled {
            // `.onDrag`, not `.draggable`: `.draggable` claimed the first mouse-down as a possible
            // drag and swallowed the click, so opening a task took two or three attempts. Gating
            // it on `isSelected` fixed the click but meant an UNSELECTED row could not be dragged
            // at all — which is why drag-and-drop read as missing (task 83f45d49). `.onDrag` only
            // begins once the pointer moves past a threshold, so a click and a drag coexist.
            content
                .highPriorityGesture(TapGesture().onEnded { onSelect() })
                .onDrag { NSItemProvider(object: dragId as NSString) }
        } else {
            content
        }
    }
}
#endif
