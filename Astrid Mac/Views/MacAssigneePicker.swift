//  MacAssigneePicker.swift
//  Who a task is assigned to — with faces.
//
//  This was a bare `Picker`, so it showed a name and a stepper and no photo, while the Mac
//  already had MacAssigneeAvatar sitting unused next to it.
//
//  It is a POPOVER of real rows rather than a Menu, for the same reason the priority picker
//  is: AppKit renders menu items in the system's own style, so a custom avatar view in a menu
//  row is not reliably drawn. The control whose entire point is showing a face cannot be a
//  control that refuses to draw one.

#if os(macOS)
import SwiftUI

struct MacAssigneePicker: View {
    let options: [MacAssigneeOption]
    /// Currently assigned id; nil for unassigned.
    let selectedId: String?
    let priority: Task.Priority
    let onSelect: (String?) -> Void

    @State private var showingPicker = false

    private var selected: MacAssigneeOption? {
        options.first { $0.userId == selectedId }
    }

    var body: some View {
        Button { showingPicker = true } label: {
            HStack(spacing: 6) {
                face(for: selected, size: 20)
                Text(selected?.displayName ?? NSLocalizedString("No one", comment: ""))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .fill(Color.secondary.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .help(NSLocalizedString("tasks.assignee", comment: ""))
        // Keyed on the assignee: SwiftUI reuses a view whose identity hasn't changed, which is
        // how the PREVIOUS person's photo used to stay on screen after a reassign.
        .id(AssigneeResolver.avatarIdentity(for: selectedId))
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.userId)
                        showingPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            face(for: option, size: 22)
                            Text(option.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                            if option.isCurrentUser {
                                Text(NSLocalizedString("mac.you", comment: "(you)"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if option.userId == selectedId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .macPointingHand()
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 200)
        }
    }

    /// The avatar, or the unassigned glyph — the same "U" iOS and the task rows use, because
    /// unassigned is a state in its own right rather than an absence.
    @ViewBuilder
    private func face(for option: MacAssigneeOption?, size: CGFloat) -> some View {
        if let user = option?.user {
            MacAssigneeAvatar(user: user, priority: priority, size: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(Color.secondary.opacity(0.15))
                Text(TaskLeadingControl.unassignedGlyph)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25)
                    .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: 2)
            )
        }
    }
}
#endif
