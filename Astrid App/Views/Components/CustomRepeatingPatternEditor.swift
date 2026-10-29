import SwiftUI

/// Custom repeating pattern editor (matching web app functionality)
/// Allows full configuration of custom repeat patterns with all options
struct CustomRepeatingPatternEditor: View {
    @Environment(\.colorScheme) var colorScheme

    @Binding var pattern: CustomRepeatingPattern
    @Binding var repeatFrom: Task.RepeatFromMode
    let onSave: () -> Void
    let onCancel: () -> Void
    /// The task's due date, so a weekly repeat with no day picked takes the due date's (AITD-550).
    var dueDate: Date? = nil
    var isAllDay: Bool = false

    @State private var showEndDatePicker = false

    // Local state for pickers - synced with pattern binding
    @State private var localInterval: Int = 1
    @State private var localMonthDay: Int = 1
    @State private var localDay: Int = 1
    @State private var localEndAfterOccurrences: Int = 1

    private let weekdays: [(value: String, label: String, short: String)] = [
        ("monday", "Monday", "M"),
        ("tuesday", "Tuesday", "T"),
        ("wednesday", "Wednesday", "W"),
        ("thursday", "Thursday", "T"),
        ("friday", "Friday", "F"),
        ("saturday", "Saturday", "S"),
        ("sunday", "Sunday", "S")
    ]

    private let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing16) {
                // Title
                HStack {
                    Text(NSLocalizedString("repeating.custom_pattern", comment: ""))
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Spacer()
                }


                // Basic settings: Interval + Unit
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text(NSLocalizedString("repeating.repeat_every", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    HStack(spacing: Theme.spacing8) {
                        // Interval picker (1-99) - using UIKit picker
                        UIKitWheelPicker(range: 1...99, selection: $localInterval)
                            .frame(width: 60, height: 100)
                            .onChange(of: localInterval) { _, newValue in
                                pattern.interval = newValue
                            }

                        // Unit picker
                        Menu {
                            Button(NSLocalizedString("repeating.days", comment: "")) { pattern.unit = "days" }
                            Button(NSLocalizedString("repeating.weeks", comment: "")) {
                                pattern.unit = "weeks"
                                requireWeekday()
                            }
                            Button(NSLocalizedString("repeating.months", comment: "")) { pattern.unit = "months" }
                            Button(NSLocalizedString("repeating.years", comment: "")) { pattern.unit = "years" }
                        } label: {
                            HStack {
                                Text(pattern.unit?.capitalized ?? "Days")
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                            .padding(Theme.spacing8)
                            .frame(maxWidth: .infinity)
                            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        }
                    }
                }

                // Week-specific settings
                if pattern.unit == "weeks" {
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        Text(NSLocalizedString("repeating.repeat_on_days", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                        HStack(spacing: Theme.spacing4) {
                            ForEach(weekdays, id: \.value) { day in
                                weekdayButton(day: day)
                            }
                        }
                    }
                }

                // Month-specific settings
                if pattern.unit == "months" {
                    VStack(alignment: .leading, spacing: Theme.spacing12) {
                        Text(NSLocalizedString("repeating.repeat_type", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                        Menu {
                            Button(NSLocalizedString("repeating.same_date_monthly", comment: "")) {
                                pattern.monthRepeatType = "same_date"
                                pattern.monthDay = 1
                                localMonthDay = 1
                                pattern.monthWeekday = nil
                            }
                            Button(NSLocalizedString("repeating.same_weekday_monthly", comment: "")) {
                                pattern.monthRepeatType = "same_weekday"
                                pattern.monthWeekday = CustomRepeatingPattern.MonthWeekday(
                                    weekday: "monday",
                                    weekOfMonth: 1
                                )
                                pattern.monthDay = nil
                            }
                        } label: {
                            HStack {
                                Text(pattern.monthRepeatType == "same_date"
                                     ? NSLocalizedString("repeating.same_date_monthly", comment: "")
                                     : NSLocalizedString("repeating.same_weekday_monthly", comment: ""))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                            .padding(Theme.spacing12)
                            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        }

                        if pattern.monthRepeatType == "same_date" {
                            VStack(alignment: .leading, spacing: Theme.spacing8) {
                                Text(NSLocalizedString("repeating.day_of_month", comment: ""))
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                                UIKitWheelPicker(range: 1...31, selection: $localMonthDay)
                                    .frame(width: 60, height: 100)
                                    .onChange(of: localMonthDay) { _, newValue in
                                        pattern.monthDay = newValue
                                    }
                            }
                        }

                        if pattern.monthRepeatType == "same_weekday" {
                            HStack(spacing: Theme.spacing12) {
                                // Weekday picker
                                VStack(alignment: .leading, spacing: Theme.spacing8) {
                                    Text(NSLocalizedString("repeating.weekday", comment: ""))
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                                    Menu {
                                        ForEach(weekdays, id: \.value) { day in
                                            Button(day.label) {
                                                pattern.monthWeekday?.weekday = day.value
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(pattern.monthWeekday?.weekday.capitalized ?? "Monday")
                                                .font(Theme.Typography.body())
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 12))
                                        }
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        .padding(Theme.spacing12)
                                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                    }
                                }

                                // Week of month picker
                                VStack(alignment: .leading, spacing: Theme.spacing8) {
                                    Text(NSLocalizedString("repeating.week_of_month", comment: ""))
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                                    Menu {
                                        ForEach(CustomRepeatSummary.weekOfMonthChoices, id: \.value) { choice in
                                            Button(NSLocalizedString(choice.labelKey, comment: "")) {
                                                pattern.monthWeekday?.weekOfMonth = choice.value
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(weekOfMonthLabel(pattern.monthWeekday?.weekOfMonth ?? 1))
                                                .font(Theme.Typography.body())
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 12))
                                        }
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        .padding(Theme.spacing12)
                                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                    }
                                }
                            }
                        }
                    }
                }

                // Year-specific settings
                if pattern.unit == "years" {
                    HStack(spacing: Theme.spacing12) {
                        // Month picker
                        VStack(alignment: .leading, spacing: Theme.spacing8) {
                            Text(NSLocalizedString("repeating.month", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                            Menu {
                                ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                                    Button(month) {
                                        pattern.month = index + 1
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(pattern.month.flatMap { months[safe: $0 - 1] } ?? "January")
                                        .font(Theme.Typography.body())
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .padding(Theme.spacing12)
                                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            }
                        }

                        // Day picker
                        VStack(alignment: .leading, spacing: Theme.spacing8) {
                            Text(NSLocalizedString("repeating.day", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                            UIKitWheelPicker(range: 1...31, selection: $localDay)
                                .frame(width: 60, height: 100)
                                .onChange(of: localDay) { _, newValue in
                                    pattern.day = newValue
                                }
                        }
                    }
                }

                // Repeat Mode (from due date vs completion date)
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text(NSLocalizedString("repeating.repeat_mode", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    VStack(spacing: Theme.spacing4) {
                        ForEach([Task.RepeatFromMode.COMPLETION_DATE, Task.RepeatFromMode.DUE_DATE], id: \.self) { mode in
                            Button {
                                repeatFrom = mode
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        Text(mode == .COMPLETION_DATE
                                             ? NSLocalizedString("repeating.from_completion", comment: "")
                                             : NSLocalizedString("repeating.from_due_date", comment: ""))
                                            .font(Theme.Typography.caption2())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    }
                                    Spacer()
                                    if repeatFrom == mode {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, Theme.spacing12)
                                .padding(.vertical, Theme.spacing8)
                                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // End conditions
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text(NSLocalizedString("repeating.end_condition", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    Menu {
                        Button(NSLocalizedString("repeating.never", comment: "")) { pattern.endCondition = "never" }
                        Button(NSLocalizedString("repeating.after_occurrences", comment: "")) {
                            pattern.endCondition = "after_occurrences"
                            if pattern.endAfterOccurrences == nil {
                                pattern.endAfterOccurrences = 1
                                localEndAfterOccurrences = 1
                            }
                        }
                        Button(NSLocalizedString("repeating.until_date", comment: "")) { pattern.endCondition = "until_date" }
                    } label: {
                        HStack {
                            Text(endConditionLabel)
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                        .padding(Theme.spacing12)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }

                    if pattern.endCondition == "after_occurrences" {
                        VStack(alignment: .leading, spacing: Theme.spacing8) {
                            Text(NSLocalizedString("repeating.num_occurrences", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                            UIKitWheelPicker(range: 1...99, selection: $localEndAfterOccurrences)
                                .frame(width: 60, height: 100)
                                .onChange(of: localEndAfterOccurrences) { _, newValue in
                                    pattern.endAfterOccurrences = newValue
                                }
                        }
                    }

                    if pattern.endCondition == "until_date" {
                        VStack(alignment: .leading, spacing: Theme.spacing8) {
                            Text(NSLocalizedString("repeating.end_date", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                            DatePicker(
                                NSLocalizedString("repeating.end_date", comment: ""),
                                selection: Binding(
                                    get: { pattern.endUntilDate ?? Date() },
                                    set: { pattern.endUntilDate = $0 }
                                ),
                                in: Date()...,  // Only allow future dates
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                // Preview summary
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text(NSLocalizedString("repeating.preview", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    Text(getPatternSummary())
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .padding(Theme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.info.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }

                // Actions
                HStack(spacing: Theme.spacing12) {
                    Button(NSLocalizedString("misc.cancel", comment: "")) {
                        onCancel()
                    }
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                    Button(NSLocalizedString("misc.close", comment: "Close")) {
                        requireWeekday()
                        onSave()
                    }
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .padding(.top, Theme.spacing8)
            }
            .padding(Theme.spacing16)
        }
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
        .onAppear {
            // Initialize local state from pattern
            localInterval = max(1, pattern.interval ?? 1)
            localMonthDay = max(1, min(31, pattern.monthDay ?? 1))
            localDay = max(1, min(31, pattern.day ?? 1))
            localEndAfterOccurrences = max(1, pattern.endAfterOccurrences ?? 1)
            requireWeekday()
        }
    }

    // MARK: - Helper Views

    private func weekdayButton(day: (value: String, label: String, short: String)) -> some View {
        let isSelected = pattern.weekdays?.contains(day.value) ?? false

        return Button {
            toggleWeekday(day.value)
        } label: {
            Text(day.short)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : (colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted))
                .frame(width: 32, height: 32)
                .background(isSelected ? Theme.accent : (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Functions

    /// A weekly repeat with no day never comes back (AITD-550): show the due date's day selected
    /// as soon as Weeks is chosen, and never save one without a day.
    private func requireWeekday() {
        let required = pattern.requiringWeekday(dueDate: dueDate, isAllDay: isAllDay)
        if required != pattern { pattern = required }
    }

    private func toggleWeekday(_ weekday: String) {
        var weekdays = pattern.weekdays ?? []
        if weekdays.contains(weekday) {
            weekdays.removeAll { $0 == weekday }
        } else {
            weekdays.append(weekday)
        }

        // Ensure at least one weekday is selected
        if !weekdays.isEmpty {
            pattern.weekdays = weekdays
        }
    }

    private var endConditionLabel: String {
        switch pattern.endCondition {
        case "never": return NSLocalizedString("repeating.never", comment: "")
        case "after_occurrences": return NSLocalizedString("repeating.after_occurrences", comment: "")
        case "until_date": return NSLocalizedString("repeating.until_date", comment: "")
        default: return NSLocalizedString("repeating.never", comment: "")
        }
    }

    private func ordinal(_ num: Int) -> String {
        if num >= 11 && num <= 13 { return "\(num)th" }
        switch num % 10 {
        case 1: return "\(num)st"
        case 2: return "\(num)nd"
        case 3: return "\(num)rd"
        default: return "\(num)th"
        }
    }

    private func weekOfMonthLabel(_ week: Int) -> String {
        guard let choice = CustomRepeatSummary.weekOfMonthChoices.first(where: { $0.value == week }) else {
            return ordinal(week)
        }
        return NSLocalizedString(choice.labelKey, comment: "")
    }

    private func getPatternSummary() -> String {
        let interval = pattern.interval ?? 1
        let unit = pattern.unit ?? "days"

        var summary = "Every \(interval) \(unit)"

        switch unit {
        case "weeks":
            if let weekdays = pattern.weekdays, !weekdays.isEmpty {
                let dayNames = weekdays.map { $0.capitalized }.joined(separator: ", ")
                summary += " on \(dayNames)"
            }

        case "months":
            if pattern.monthRepeatType == "same_date", let day = pattern.monthDay {
                summary += " on the \(ordinal(day))"
            } else if pattern.monthRepeatType == "same_weekday", let monthWeekday = pattern.monthWeekday {
                summary += " on the \(CustomRepeatSummary.weekOfMonth(monthWeekday.weekOfMonth)) \(monthWeekday.weekday.capitalized)"
            }

        case "years":
            if let month = pattern.month, let day = pattern.day {
                let monthName = months[safe: month - 1] ?? "January"
                summary += " on \(monthName) \(ordinal(day))"
            }

        default:
            break
        }

        if pattern.endCondition == "after_occurrences", let count = pattern.endAfterOccurrences {
            summary += " (\(count) times)"
        } else if pattern.endCondition == "until_date", let endDate = pattern.endUntilDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            summary += " until \(formatter.string(from: endDate))"
        }

        // Add repeat mode
        if repeatFrom == .DUE_DATE {
            summary += ", from due date"
        } else {
            summary += ", from completion"
        }

        return summary
    }
}

// MARK: - Array Extension for Safe Access

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
