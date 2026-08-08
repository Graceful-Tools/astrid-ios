//  MacDueDatePicker.swift
//  Astrid for Mac — the iOS due-date control, ported.
//
//  A trigger that reads the date (or "No due date"), and a popover carrying the
//  quick picks and the calendar. See MacWhenRow.swift for what this replaced and
//  why; MacWhenRowTests pins the composition.

#if os(macOS)
import SwiftUI

/// Shared chrome for a trigger in the When row, so date, time and repeat read as
/// one control each rather than three different kinds of button.
private struct MacWhenTriggerLabel: View {
    let text: String
    let systemImage: String
    /// Muted when the control has no value — "No due date" is a prompt, not data.
    let isPlaceholder: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isPlaceholder ? Theme.textMuted : Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// One selectable row inside a picker popover.
private struct MacPickerRow: View {
    let title: String
    var isDestructive: Bool = false
    var isChecked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(isDestructive ? Theme.error : Theme.textPrimary)
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDestructive ? Theme.error : Theme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macPointingHand()
    }
}

/// The due-date control: trigger + popover.
struct MacDueDatePicker: View {
    /// nil means the task has no due date.
    @Binding var date: Date?
    let isAllDay: Bool
    let onCommit: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            MacWhenTriggerLabel(
                text: DueDateLabel.text(for: date, isAllDay: isAllDay),
                systemImage: "calendar",
                isPlaceholder: date == nil
            )
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(MacDueDatePopover.rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .clear:
                        // A CHOICE, first, in red — not a toolbar escape hatch.
                        MacPickerRow(title: NSLocalizedString("picker.no_due_date", comment: ""),
                                     isDestructive: true,
                                     isChecked: date == nil) {
                            date = nil
                            isPresented = false
                            onCommit()
                        }
                    case .quickPick(let option):
                        MacPickerRow(title: NSLocalizedString(option.titleKey, comment: ""),
                                     isChecked: isOn(daysFromToday: option.daysFromToday)) {
                            // The quick pick names a DAY, counted from today —
                            // never from the task's existing date, or "Today" on
                            // a task due in March would mean March.
                            select(localDay: DueDateQuickPicks.date(daysFromToday: option.daysFromToday,
                                                                    from: Date()))
                            isPresented = false
                        }
                    case .calendar:
                        Divider().padding(.vertical, 4)
                        DatePicker("", selection: calendarSelection,
                                   displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .frame(maxWidth: 260)
                    }
                }
            }
            .padding(10)
            .frame(width: 280)
        }
    }

    /// What the calendar shows and sets — always a LOCAL day, converted to and
    /// from storage form on the way through.
    private var calendarSelection: Binding<Date> {
        Binding(
            get: {
                guard let date else { return Date() }
                return isAllDay ? MacWhenDate.localDay(ofAllDay: date) : date
            },
            set: { select(localDay: $0) }
        )
    }

    /// Store a local calendar day, preserving whatever the task's other half
    /// holds: an all-day task keeps its UTC-midnight form, a timed one keeps
    /// its time.
    private func select(localDay day: Date) {
        if isAllDay {
            date = MacWhenDate.utcMidnight(ofLocalDay: day)
        } else {
            date = MacWhenDate.combining(day: day, timeFrom: date)
        }
        onCommit()
    }

    private func isOn(daysFromToday days: Int) -> Bool {
        guard let date else { return false }
        return DueDateLabel.dayOffset(to: date, isAllDay: isAllDay) == days
    }
}

/// The time control. Clearing the time is what makes a task all-day, which is
/// why the standalone "All day" toggle is gone.
struct MacDueTimePicker: View {
    /// The task's stored due date. The time control owns its time-of-day half.
    @Binding var due: Date
    /// All-day IS "no time" — there is no separate toggle, as on iOS.
    @Binding var isAllDay: Bool
    let onCommit: () -> Void

    @State private var isPresented = false

    /// nil while the task is all-day.
    private var time: Date? { isAllDay ? nil : due }

    private var label: String {
        guard let time else { return NSLocalizedString("picker.all_day", comment: "All day") }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    /// Give the task a time. Coming from all-day, the stored value is midnight
    /// UTC — read its LOCAL day first, or setting "Morning" on a task due the
    /// 8th quietly moves it to the 7th for anyone west of UTC.
    private func setTime(_ newTime: Date) {
        let day = isAllDay ? MacWhenDate.localDay(ofAllDay: due) : due
        due = MacWhenDate.combining(day: day, timeFrom: newTime)
        isAllDay = false
        onCommit()
    }

    /// Back to all-day: re-express the current local day as midnight UTC.
    private func clearTime() {
        due = MacWhenDate.utcMidnight(ofLocalDay: due)
        isAllDay = true
        onCommit()
    }

    var body: some View {
        Button { isPresented = true } label: {
            MacWhenTriggerLabel(text: label,
                                systemImage: time == nil ? "clock.badge.xmark" : "clock",
                                isPlaceholder: time == nil)
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(MacDueTimePopover.rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .clear:
                        MacPickerRow(title: NSLocalizedString("picker.all_day", comment: ""),
                                     isDestructive: true,
                                     isChecked: time == nil) {
                            clearTime()
                            isPresented = false
                        }
                    case .quickPick(let option):
                        MacPickerRow(title: NSLocalizedString(option.titleKey, comment: ""),
                                     isChecked: isOn(hour: option.hour)) {
                            setTime(DueDateQuickPicks.applying(hour: option.hour,
                                                               to: time ?? Date()))
                            isPresented = false
                        }
                    case .clock:
                        Divider().padding(.vertical, 4)
                        DatePicker("", selection: Binding(get: { time ?? Date() },
                                                          set: { setTime($0) }),
                                   displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(10)
            .frame(width: 220)
        }
    }

    private func isOn(hour: Int) -> Bool {
        guard let time else { return false }
        return Calendar.current.component(.hour, from: time) == hour
            && Calendar.current.component(.minute, from: time) == 0
    }
}
#endif
