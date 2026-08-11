//  MacDueDatePicker.swift
//  Astrid for Mac — the iOS due-date control, ported.
//
//  A trigger that reads the date (or "No due date"), and a popover carrying the
//  quick picks and the calendar. See MacWhenRow.swift for what this replaced and
//  why; MacWhenRowTests pins the composition.

#if os(macOS)
import SwiftUI

/// The due-date control: trigger + popover.
struct MacDueDatePicker: View {
    /// nil means the task has no due date.
    @Binding var date: Date?
    /// A binding, not a value: dating a task that had no date TURNS IT all-day, so the
    /// picker has to be able to say so (task 0b057b7a).
    @Binding var isAllDay: Bool
    let onCommit: () -> Void

    @State private var isPresented = false
    /// What the user has typed, mirrored from `date` while the popover is open.
    @State private var typed = ""
    /// A parsed-but-uncommitted date, so the calendar can follow the typing
    /// without saving on every keystroke.
    @State private var preview: Date?
    /// How wide the scaled calendar actually is. The popover is built around it rather than
    /// around a hand-picked number (task d4f663a3); the estimate covers the first pass.
    @State private var calendarWidth = MacFieldPicker.calendarNaturalEstimate.width
                                     * MacFieldPicker.calendarScale

    /// Accept a typed date, or leave the field showing what is actually set.
    private func commitTyped() {
        if let parsed = MacDateEntry.parse(typed) {
            select(localDay: parsed)
            isPresented = false
        } else {
            typed = date.map { MacDateEntry.format($0) } ?? ""
        }
    }

    var body: some View {
        Button { isPresented = true } label: {
            // No glyph: the row leads with a calendar icon, so one inside the
            // chip says the same thing twice on one line.
            MacFieldTrigger(text: DueDateLabel.text(for: date, isAllDay: isAllDay),
                            isPlaceholder: date == nil)
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .center, spacing: MacFieldPicker.rowSpacing) {
                ForEach(Array(MacDueDatePopover.rows.enumerated()), id: \.offset) { _, row in
                    switch row {
                    case .typedEntry:
                        // OUR field, not NSDatePicker's. `.field` types but drags
                        // the system's own calendar overlay in on top of ours;
                        // `.graphical` can be sized and centred but cannot be
                        // typed into at all. Owning the text field decouples the
                        // two, and MacDateEntry makes the parsing testable.
                        TextField(MacDateEntry.format(Date()), text: $typed)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .onSubmit(commitTyped)
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                typed = date.map { MacDateEntry.format($0) } ?? ""
                                preview = nil
                            }
                            .onChange(of: date) { _, newValue in
                                typed = newValue.map { MacDateEntry.format($0) } ?? ""
                                preview = nil
                            }
                            // The calendar FOLLOWS the typing: each keystroke that
                            // parses moves the grid to that day, so you can see
                            // where you are landing before committing. Nothing is
                            // saved until Return or a click on the calendar.
                            .onChange(of: typed) { _, text in
                                if let parsed = MacDateEntry.parse(text) { preview = parsed }
                            }
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
                        Divider().padding(.vertical, 2)
                        // Scaled and centred. `scaleEffect` does not change layout,
                        // so MacScaled measures the natural size and reserves
                        // scale x that — otherwise the grid overlaps what sits
                        // above it or gets clipped by a guessed frame.
                        MacScaled(scale: MacFieldPicker.calendarScale,
                                  onReserve: { calendarWidth = $0.width }) {
                            DatePicker("", selection: calendarSelection,
                                       displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(MacFieldPicker.padding)
            // The popover follows the CALENDAR, so the calendar fills it. A fixed 300 left the
            // 208.5pt scaled grid floating with dead space down both sides (task d4f663a3).
            .frame(width: MacFieldPicker.popoverWidth(forCalendarWidth: calendarWidth))
        }
    }

    /// What the calendar shows and sets — always a LOCAL day, converted to and
    /// from storage form on the way through.
    private var calendarSelection: Binding<Date> {
        Binding(
            get: {
                if let preview { return preview }
                guard let date else { return Date() }
                return isAllDay ? MacWhenDate.localDay(ofAllDay: date) : date
            },
            set: { preview = nil; select(localDay: $0) }
        )
    }

    /// Store a local calendar day, preserving whatever the task's other half
    /// holds: an all-day task keeps its UTC-midnight form, a timed one keeps
    /// its time.
    private func select(localDay day: Date) {
        // Decide BEFORE writing the date, since the rule turns on whether one existed.
        let allDay = MacNewDueDate.isAllDay(existingDate: date, currentIsAllDay: isAllDay)
        isAllDay = allDay
        if allDay {
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
            MacFieldTrigger(text: label,
                            systemImage: time == nil ? "clock.badge.xmark" : "clock",
                            isPlaceholder: time == nil)
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .center, spacing: MacFieldPicker.rowSpacing) {
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
                        // Typable here too, for the same reason.
                        DatePicker("", selection: Binding(get: { time ?? Date() },
                                                          set: { setTime($0) }),
                                   displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.field)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(MacFieldPicker.padding)
            .frame(width: MacFieldPicker.narrowPopoverWidth)
        }
    }

    private func isOn(hour: Int) -> Bool {
        guard let time else { return false }
        return Calendar.current.component(.hour, from: time) == hour
            && Calendar.current.component(.minute, from: time) == 0
    }
}
#endif
