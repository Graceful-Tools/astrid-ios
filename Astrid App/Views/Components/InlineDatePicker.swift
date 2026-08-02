import SwiftUI

/// Inline date picker that shows the current date and allows editing
struct InlineDatePicker: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    @Binding var date: Date?
    var onSave: (() -> Void)?
    var showLabel: Bool = true
    var isAllDay: Bool = true  // Whether this is an all-day task (affects timezone handling)
    /// Sizes the trigger to its content instead of filling the row, so Date, Time and Repeat can
    /// share one line in the task detail (Task 42013da7).
    var compact: Bool = false

    @State private var showingPicker = false

    // Quick date options (matching mobile web)
    private let quickOptions: [(String, Int)] = [
        ("Today", 0),
        ("Tomorrow", 1),
        ("In 3 days", 3),
        ("Next week", 7)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if showLabel {
                Text(label)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            Button(action: { showingPicker = true }) {
                HStack(spacing: Theme.spacing4) {
                    if let date = date {
                        Text(formatDate(date))
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .lineLimit(1)
                            // Never truncate in a shared row — "Jul…" is not a date (42013da7).
                            .fixedSize(horizontal: compact, vertical: false)
                    } else if !compact {
                        Text(NSLocalizedString("picker.no_due_date", comment: "No due date"))
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            .lineLimit(1)
                    }
                    if !compact { Spacer() }
                    // With a date set, compact shows the date alone — the calendar glyph is only
                    // needed as the "no date yet" affordance.
                    if !compact || date == nil {
                        Image(systemName: "calendar")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
                .padding(.horizontal, compact ? Theme.spacing8 : Theme.spacing12)
                .padding(.vertical, compact ? Theme.spacing4 : Theme.spacing12)
                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingPicker) {
                NavigationStack {
                    VStack(spacing: Theme.spacing16) {
                        // Quick date options
                        VStack(spacing: Theme.spacing8) {
                            ForEach(quickOptions, id: \.1) { option in
                                Button {
                                    setQuickDate(daysFromNow: option.1)
                                } label: {
                                    HStack {
                                        Text(option.0)
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        Spacer()
                                        if let date = date, Calendar.current.isDate(date, equalTo: Date().addingTimeInterval(TimeInterval(option.1 * 86400)), toGranularity: .day) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, Theme.spacing16)
                                    .padding(.vertical, Theme.spacing12)
                                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.spacing16)

                        Divider()
                            .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)
                            .padding(.horizontal, Theme.spacing16)

                        // Custom date picker
                        VStack(alignment: .leading, spacing: Theme.spacing8) {
                            Text(NSLocalizedString("picker.custom_date", comment: "Custom Date"))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                .padding(.horizontal, Theme.spacing16)

                            DatePicker(
                                "Select Date",
                                selection: Binding(
                                    get: {
                                        // For all-day tasks: Convert UTC midnight to local calendar date
                                        // This ensures the picker shows the correct calendar day
                                        guard let existingDate = date else { return Date() }

                                        if isAllDay {
                                            // Extract UTC date components and create local date
                                            var utcCalendar = Calendar(identifier: .gregorian)
                                            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
                                            let components = utcCalendar.dateComponents([.year, .month, .day], from: existingDate)

                                            // Create date in local calendar with same day/month/year
                                            let localCalendar = Calendar.current
                                            if let localDate = localCalendar.date(from: components) {
                                                return localDate
                                            }
                                        }

                                        return existingDate
                                    },
                                    set: { newDate in
                                        // For all-day tasks: Convert selected local date to UTC midnight
                                        // This ensures storage matches Google Calendar spec
                                        if isAllDay {
                                            // Extract day/month/year from selected date (in local timezone)
                                            let localCalendar = Calendar.current
                                            let components = localCalendar.dateComponents([.year, .month, .day], from: newDate)

                                            guard let year = components.year, let month = components.month, let day = components.day else {
                                                date = newDate
                                                return
                                            }

                                            // Create date at midnight UTC with same day/month/year
                                            // Use fresh Gregorian calendar to avoid device settings interference
                                            var utcCalendar = Calendar(identifier: .gregorian)
                                            utcCalendar.timeZone = TimeZone(identifier: "UTC")!

                                            // Build DateComponents explicitly (inline initializer can cause issues)
                                            var utcComponents = DateComponents()
                                            utcComponents.year = year
                                            utcComponents.month = month
                                            utcComponents.day = day
                                            utcComponents.hour = 0
                                            utcComponents.minute = 0
                                            utcComponents.second = 0

                                            if let utcMidnight = utcCalendar.date(from: utcComponents) {
                                                date = utcMidnight
                                            } else {
                                                date = newDate
                                            }
                                        } else {
                                            date = newDate
                                        }

                                        // Auto-save and close after selection
                                        _Concurrency.Task {
                                            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 0.3s delay
                                            await MainActor.run {
                                                onSave?()
                                                showingPicker = false
                                            }
                                        }
                                    }
                                ),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                            .padding(.horizontal, Theme.spacing8)
                        }

                        Spacer()
                    }
                    .padding(.top, Theme.spacing16)
                    .navigationTitle(label)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Clear") {
                                date = nil
                                showingPicker = false
                                onSave?()
                            }
                        }
                    }
                }
            }
        }
    }

    private func setQuickDate(daysFromNow: Int) {
        // CRITICAL: Use local calendar to get target day, then convert to UTC midnight
        // This ensures "Today" means the user's local calendar day, not UTC day
        // Fix for bug where 4pm PT on Nov 22 was creating Nov 23 (because PT is behind UTC)

        // Get target day in local calendar
        let localCalendar = Calendar.current
        guard let targetLocalDate = localCalendar.date(byAdding: .day, value: daysFromNow, to: Date()) else { return }

        // Extract year/month/day from local calendar
        let components = localCalendar.dateComponents([.year, .month, .day], from: targetLocalDate)
        guard let year = components.year, let month = components.month, let day = components.day else { return }

        // Create date at midnight UTC with same year/month/day
        // Use fresh Gregorian calendar to avoid device settings interference
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        // Build DateComponents explicitly (inline initializer can cause issues)
        var utcComponents = DateComponents()
        utcComponents.year = year
        utcComponents.month = month
        utcComponents.day = day
        utcComponents.hour = 0
        utcComponents.minute = 0
        utcComponents.second = 0

        if let utcMidnight = utcCalendar.date(from: utcComponents) {
            date = utcMidnight
            showingPicker = false
            onSave?()
        }
    }

    private func formatDate(_ date: Date) -> String {
        // CRITICAL: Use UTC calendar for all-day tasks (stored at midnight UTC)
        // Use local calendar for timed tasks (stored with specific time in UTC)
        // This prevents timezone offset bugs (e.g., "Tomorrow" showing for "Today" when time is set)

        if isAllDay {
            // All-day tasks: Extract and compare UTC date components directly
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!

            // Get today in LOCAL calendar
            let localCalendar = Calendar.current
            let now = Date()
            let todayLocal = localCalendar.dateComponents([.year, .month, .day], from: now)

            // Create UTC midnight for today's LOCAL date
            var todayUTCComponents = DateComponents()
            todayUTCComponents.year = todayLocal.year
            todayUTCComponents.month = todayLocal.month
            todayUTCComponents.day = todayLocal.day
            todayUTCComponents.hour = 0
            todayUTCComponents.minute = 0
            todayUTCComponents.second = 0

            guard let todayUTC = utcCalendar.date(from: todayUTCComponents) else {
                return date.description
            }

            // Extract UTC date components from the stored date
            let dateComponents = utcCalendar.dateComponents([.year, .month, .day], from: date)

            // Compare the components directly
            let daysDiff = utcCalendar.dateComponents([.day], from: todayUTC, to: utcCalendar.date(from: dateComponents) ?? date).day ?? 0

            if daysDiff == 0 {
                return "Today"
            } else if daysDiff == 1 {
                return "Tomorrow"
            } else if daysDiff == -1 {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                formatter.timeZone = TimeZone(identifier: "UTC")
                return formatter.string(from: date)
            }
        } else {
            // Timed tasks: Use local calendar
            let localCalendar = Calendar.current
            let today = localCalendar.startOfDay(for: Date())
            let compareDate = localCalendar.startOfDay(for: date)

            let daysDiff = localCalendar.dateComponents([.day], from: today, to: compareDate).day ?? 0

            if daysDiff == 0 {
                return "Today"
            } else if daysDiff == 1 {
                return "Tomorrow"
            } else if daysDiff == -1 {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return formatter.string(from: date)
            }
        }
    }
}
