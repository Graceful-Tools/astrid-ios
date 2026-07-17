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
    static func make(interval: Int, unit: String, endCondition: String,
                     endAfter: Int, endUntil: Date) -> CustomRepeatingPattern {
        var p = CustomRepeatingPattern(
            type: "custom", unit: unit, interval: max(1, interval), endCondition: endCondition,
            endAfterOccurrences: nil, endUntilDate: nil, weekdays: nil,
            monthRepeatType: nil, monthDay: nil, monthWeekday: nil, month: nil, day: nil)
        if endCondition == "after_occurrences" { p.endAfterOccurrences = max(1, endAfter) }
        if endCondition == "until_date" { p.endUntilDate = endUntil }
        return p
    }

    /// Human summary for the detail row.
    static func summary(_ p: CustomRepeatingPattern) -> String {
        let n = max(1, p.interval ?? 1)
        let unit = p.unit ?? "weeks"
        let base = n == 1 ? "Every \(singular(unit))" : "Every \(n) \(unit)"
        switch p.endCondition {
        case "after_occurrences": return "\(base), \(p.endAfterOccurrences ?? 0)×"
        case "until_date": return "\(base), until date"
        default: return base
        }
    }

    private static func singular(_ unit: String) -> String {
        unit.hasSuffix("s") ? String(unit.dropLast()) : unit
    }
}

struct MacCustomRepeatEditor: View {
    @Environment(\.dismiss) private var dismiss
    let initial: CustomRepeatingPattern?
    let onSave: (CustomRepeatingPattern) -> Void

    @State private var interval = 1
    @State private var unit = "weeks"
    @State private var endCondition = "never"
    @State private var endAfter = 10
    @State private var endUntil = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Repeat").font(.headline)

            HStack {
                Text("Every")
                Stepper(value: $interval, in: 1...99) { Text("\(interval)") }.frame(width: 90)
                Picker("", selection: $unit) {
                    ForEach(MacCustomRepeat.units, id: \.self) { Text($0.capitalized).tag($0) }
                }.labelsHidden().frame(width: 120)
            }

            Picker("Ends", selection: $endCondition) {
                Text("Never").tag("never")
                Text("After occurrences").tag("after_occurrences")
                Text("On date").tag("until_date")
            }
            if endCondition == "after_occurrences" {
                Stepper(value: $endAfter, in: 1...999) { Text("\(endAfter) occurrences") }
            } else if endCondition == "until_date" {
                DatePicker("Until", selection: $endUntil, displayedComponents: [.date])
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    onSave(MacCustomRepeat.make(interval: interval, unit: unit,
                                                endCondition: endCondition, endAfter: endAfter, endUntil: endUntil))
                    dismiss()
                }.buttonStyle(.borderedProminent)
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
            }
        }
    }
}
#endif
