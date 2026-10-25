//  MacCustomRepeatEditor.swift
//  Astrid for Mac — custom repeat editor (Task 1b5f2810): "every N days/weeks/months/years"
//  with an end condition. Builds a CustomRepeatingPattern for TaskService.updateTask.
//  (Per-task reminder overrides need a service-layer addition and are tracked separately.)

#if os(macOS)
import SwiftUI

enum MacCustomRepeat {
    static let units = ["days", "weeks", "months", "years"]
    static let endConditions = ["never", "after_occurrences", "until_date"]

    /// Build a normalized custom pattern from the editor inputs.
    ///
    /// A weekly pattern always names its days (AITD-550): the ones picked, or the due date's.
    /// This wrote `weekdays: nil` for every weekly repeat, which the shared rule reads as nothing
    /// to repeat on — so the series ended at its first completion.
    static func make(interval: Int, unit: String, endCondition: String,
                     endAfter: Int, endUntil: Date,
                     weekdays: [String]? = nil, dueDate: Date? = nil, isAllDay: Bool = false,
                     timeZone: TimeZone = .current) -> CustomRepeatingPattern {
        var p = CustomRepeatingPattern(
            type: "custom", unit: unit, interval: max(1, interval), endCondition: endCondition,
            endAfterOccurrences: nil, endUntilDate: nil,
            weekdays: unit == "weeks" && !(weekdays ?? []).isEmpty ? weekdays : nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil, month: nil, day: nil)
        if endCondition == "after_occurrences" { p.endAfterOccurrences = max(1, endAfter) }
        if endCondition == "until_date" { p.endUntilDate = endUntil }
        return p.requiringWeekday(dueDate: dueDate, isAllDay: isAllDay, timeZone: timeZone)
    }

    /// Monday first, as the iOS editor lists them; the labels are the system's own, so localized.
    static let weekdayOrder = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    /// Human summary for the detail row.
    static func summary(_ p: CustomRepeatingPattern) -> String {
        let n = max(1, p.interval ?? 1)
        let unit = ["days", "weeks", "months", "years"].contains(p.unit ?? "") ? p.unit! : "weeks"
        let base = n == 1
            ? NSLocalizedString("mac.repeat.every_one.\(unit)", comment: "")
            : String(format: NSLocalizedString("mac.repeat.every_n.\(unit)", comment: ""), n)
        switch p.endCondition {
        case "after_occurrences":
            return String(format: NSLocalizedString("mac.repeat.summary_times", comment: ""),
                          base, p.endAfterOccurrences ?? 0)
        case "until_date":
            return String(format: NSLocalizedString("mac.repeat.summary_until_date", comment: ""), base)
        default: return base
        }
    }
}

struct MacCustomRepeatEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initial: CustomRepeatingPattern?
    /// The task's due date: a weekly repeat with no day picked takes its day (AITD-550).
    var dueDate: Date? = nil
    var isAllDay: Bool = false
    let onSave: (CustomRepeatingPattern) -> Void

    @State private var interval = 1
    @State private var unit = "weeks"
    @State private var endCondition = "never"
    @State private var endAfter = 10
    @State private var endUntil = Date()
    @State private var weekdays: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("mac.custom_repeat", comment: "")).macFont(.headline)

            HStack {
                Text(NSLocalizedString("mac.every", comment: ""))
                Stepper(value: $interval, in: 1...99) { Text("\(interval)") }.frame(width: 90)
                Picker("", selection: $unit) {
                    ForEach(MacCustomRepeat.units, id: \.self) { Text(MacRepeatUnitLabel.title(for: $0)).tag($0) }
                }.labelsHidden().frame(width: 120)
            }
            if unit == "weeks" { weekdayRow }

            Picker(NSLocalizedString("mac.ends", comment: ""), selection: $endCondition) {
                Text(NSLocalizedString("never", comment: "")).tag("never")
                Text(NSLocalizedString("mac.after_occurrences", comment: "")).tag("after_occurrences")
                Text(NSLocalizedString("mac.on_date", comment: "")).tag("until_date")
            }
            if endCondition == "after_occurrences" {
                Stepper(value: $endAfter, in: 1...999) {
                    Text(String(format: NSLocalizedString("mac.occurrences_count", comment: ""), endAfter))
                }
            } else if endCondition == "until_date" {
                DatePicker(NSLocalizedString("mac.until", comment: ""), selection: $endUntil, displayedComponents: [.date])
            }

            // Centred, like every other button in the field popovers (task d4f663a3). A lone
            // leading Spacer pinned these two to the right while the choice rows they replace
            // sit centred — the same popover, laid out two ways.
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button(NSLocalizedString("actions.save", comment: "")) {
                    onSave(MacCustomRepeat.make(interval: interval, unit: unit,
                                                endCondition: endCondition, endAfter: endAfter, endUntil: endUntil,
                                                weekdays: weekdays, dueDate: dueDate, isAllDay: isAllDay))
                    dismiss()
                }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(20).frame(width: 340)
        .onAppear {
            if let p = initial {
                interval = p.interval ?? 1
                unit = p.unit ?? "weeks"
                endCondition = p.endCondition ?? "never"
                endAfter = p.endAfterOccurrences ?? 10
                endUntil = p.endUntilDate ?? Date()
                weekdays = p.weekdays ?? []
            }
            requireWeekday()
        }
        .onChange(of: unit) { requireWeekday() }
    }

    /// Show the due date's day selected as soon as Weeks is chosen, as iOS does (AITD-550).
    private func requireWeekday() {
        guard unit == "weeks", weekdays.isEmpty else { return }
        weekdays = MacCustomRepeat.make(interval: interval, unit: unit, endCondition: "never", endAfter: 1,
                                        endUntil: endUntil, dueDate: dueDate, isAllDay: isAllDay).weekdays ?? []
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(MacCustomRepeat.weekdayOrder, id: \.self) { day in
                let index = (CustomRepeatingPattern.weekdayNames.firstIndex(of: day) ?? 0)
                let selected = weekdays.contains(day)
                Button {
                    // The last selected day stays selected: a weekly repeat needs one.
                    if selected { if weekdays.count > 1 { weekdays.removeAll { $0 == day } } }
                    else { weekdays.append(day) }
                } label: {
                    Text(Calendar.current.veryShortStandaloneWeekdaySymbols[index])
                        .frame(width: 26, height: 26)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(Circle().fill(selected ? Theme.accent : Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[index])
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("customRepeat.weekday.\(day)")
            }
        }
    }
}
#endif
