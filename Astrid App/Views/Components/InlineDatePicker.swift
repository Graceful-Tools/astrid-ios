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

    // Quick date options — astrid-core's (`dueDateOptions`, AITD-461), which the Mac reads too:
    // the set, the order, the date each one means and which one is lit. They used to be a private
    // array here, which is exactly why the Mac had none (ea4f5124).
    @ObservedObject private var duePicks = DuePicks.shared
    /// The last picks the core gave, drawn while a new question is out.
    @State private var lastQuickOptions: [DueOptions.DatePick] = []

    private var quickOptions: [DueOptions.DatePick] {
        DuePicks.options(date, isAllDay: isAllDay)?.dates ?? lastQuickOptions
    }

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
                    } else {
                        // Words, not a bare calendar glyph: "no date" has to SAY so (42013da7).
                        // The slashed clock and repeat symbols stay — those are states you scan
                        // past, whereas an empty date is a thing you are being asked to fill in.
                        Text(NSLocalizedString("picker.no_due_date", comment: "No due date"))
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            .lineLimit(1)
                            .fixedSize(horizontal: compact, vertical: false)
                    }
                    if !compact { Spacer() }
                    // No glyph on the empty state. The calendar icon used to stand in as the
                    // "no date yet" affordance, but the words "No due date" already say that,
                    // and the row leads with a calendar icon of its own — so the placeholder
                    // was carrying two of them.
                    if !compact, date != nil {
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
                    VStack(spacing: PickerRowMetrics.sectionSpacing) {
                        // Quick date options
                        VStack(spacing: PickerRowMetrics.rowSpacing) {
                            // "No due date" is a CHOICE, not a toolbar escape hatch — it sits with
                            // the other quick picks, first, in red so it reads as the one that
                            // takes a value away (42013da7).
                            Button {
                                date = nil
                                showingPicker = false
                                onSave?()
                            } label: {
                                HStack {
                                    Text(NSLocalizedString("picker.no_due_date", comment: "No due date"))
                                        .font(Theme.Typography.body())
                                        .foregroundColor(Theme.error)
                                    Spacer()
                                    if date == nil {
                                        Image(systemName: "checkmark").foregroundColor(Theme.error)
                                    }
                                }
                                .padding(.horizontal, PickerRowMetrics.rowHorizontalPadding)
                                .padding(.vertical, PickerRowMetrics.clearRowVerticalPadding)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            }
                            .buttonStyle(.plain)

                            ForEach(quickOptions, id: \.daysFromToday) { option in
                                Button {
                                    setQuickDate(option)
                                } label: {
                                    HStack {
                                        Text(NSLocalizedString(option.titleKey, comment: ""))
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        Spacer()
                                        if option.isSelected {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, PickerRowMetrics.rowHorizontalPadding)
                                    .padding(.vertical, PickerRowMetrics.rowVerticalPadding)
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

                        // Custom date picker. No header: the calendar below is self-evident, and
                        // the label only added a line between the quick picks and the thing it
                        // was describing (42013da7).
                        VStack(alignment: .leading, spacing: PickerRowMetrics.rowSpacing) {
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
                        // "No due date" moved into the quick picks; this is just the way out.
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("actions.close", comment: "Close")) {
                                showingPicker = false
                            }
                        }
                    }
                }
            }
        }
        // Asked as the trigger appears, so the picks are there the moment the sheet opens.
        .task(id: DuePicks.key(date, isAllDay: isAllDay)) {
            await DuePicks.ask(date, isAllDay: isAllDay)
            if let picks = DuePicks.options(date, isAllDay: isAllDay)?.dates { lastQuickOptions = picks }
        }
    }

    /// A quick pick is the reader's calendar day stored as an all-day date at UTC midnight — the
    /// core's answer, the instant this always wrote (D48). "Today" is where the person is: 4pm PT
    /// on Nov 22 is the 22nd, not the 23rd it is in UTC.
    private func setQuickDate(_ option: DueOptions.DatePick) {
        guard let picked = option.date else { return }
        date = picked
        showingPicker = false
        onSave?()
    }

    /// The shared label, so iOS and Mac cannot disagree about which day a task
    /// is due. This was 70 lines of timezone arithmetic living privately here —
    /// see DueDateLabel for why it moved.
    private func formatDate(_ date: Date) -> String {
        DueDateLabel.text(for: date, isAllDay: isAllDay)
    }
}
