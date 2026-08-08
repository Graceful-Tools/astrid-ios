//  MacListPicker.swift
//  Astrid for Mac — choosing which lists a task belongs to.
//
//  There was no such control. The detail and the board card both DREW the task's
//  lists as chips, with an em-dash when there were none, and neither attached
//  anything you could click — which is what "list selecting isn't working on the
//  Mac app" turned out to mean. Not a broken control: a missing one.
//
//  Membership is multi-select (a task can live in several lists) and may be
//  empty (My Tasks only), so this is a checklist, not a single-choice menu.

#if os(macOS)
import SwiftUI

struct MacListPicker: View {
    let selectedIds: [String]
    let lists: [TaskList]
    let onToggle: (String) -> Void
    /// Owned by the caller so the "focus lists" keyboard shortcut can open it.
    @Binding var isPresented: Bool

    private var selectedLists: [TaskList] {
        selectedIds.compactMap { id in lists.first { $0.id == id } }
    }

    /// Status lists are the board's columns, not places you file a task by hand —
    /// the same filtering the rest of the app applies when offering lists.
    private var selectableLists: [TaskList] {
        lists.filter { $0.listType != "status" }
    }

    var body: some View {
        Button { isPresented = true } label: { chips }
            .buttonStyle(.plain)
            .macPointingHand()
            .accessibilityLabel(NSLocalizedString("picker.add_to_lists", comment: ""))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { picker }
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(selectedLists) { list in
                HStack(spacing: 4) {
                    MacListIcon(list: list, size: 11)
                    Text(list.name).font(MacTypography.rowMeta)
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .foregroundStyle(Theme.accent)
                .background(Theme.accent.opacity(0.15), in: Capsule())
            }
            if selectedLists.isEmpty {
                // A prompt, not an em-dash. The dash read as "this field has no
                // value" rather than "you can put one here".
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text(NSLocalizedString("picker.add_to_lists", comment: ""))
                }
                .font(MacTypography.rowMeta)
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var picker: some View {
        VStack(alignment: .leading, spacing: 2) {
            if selectableLists.isEmpty {
                Text(NSLocalizedString("picker.no_lists", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(selectableLists) { list in
                            listRow(list)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(10)
        .frame(width: 240)
    }

    private func listRow(_ list: TaskList) -> some View {
        let isOn = selectedIds.contains(list.id)
        // The popover STAYS open: membership is multi-select, and closing after
        // each pick would make adding a task to three lists three round trips.
        return Button { onToggle(list.id) } label: {
            HStack(spacing: 6) {
                MacListIcon(list: list, size: 12)
                Text(list.name).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn ? Theme.accent.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macPointingHand()
    }
}
#endif
