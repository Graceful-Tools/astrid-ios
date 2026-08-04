import SwiftUI

/// Inline time picker with quick options (matching mobile web)
/// Quick options: Morning (9 AM), Afternoon (2 PM), Evening (6 PM), Night (9 PM)
struct InlineTimePicker: View {
    @Environment(\.colorScheme) var colorScheme

    let label: String
    @Binding var time: Date?
    let onSave: (() async -> Void)?
    var showLabel: Bool = true
    /// Sizes the trigger to its content so it can share the "When" row (Task 42013da7).
    var compact: Bool = false

    @State private var isEditing = false
    @State private var selectedTime: Date = Date()

    // Picker components for compact time selection
    @State private var pickerHour: Int = 9
    @State private var pickerMinute: Int = 0
    @State private var pickerPeriod: Int = 0 // 0 = AM, 1 = PM

    // Quick time options — from the SHARED source, same reason as the date picker (ea4f5124).
    private var quickOptions: [(String, Int)] {
        DueDateQuickPicks.timeOptions.map { (NSLocalizedString($0.titleKey, comment: ""), $0.hour) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if showLabel {
                Text(label)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            // Compact triggers are chip-sized, so the inline editor would be squeezed into a few
            // points of width. It goes in a sheet instead — the same full-width presentation the
            // date picker has always used (42013da7).
            if isEditing && !compact {
                editor
            } else {
                trigger
            }
        }
        .sheet(isPresented: Binding(get: { compact && isEditing },
                                    set: { isEditing = $0 })) {
            NavigationStack {
                ScrollView {
                    editor
                        .padding(Theme.spacing16)
                        // See InlineRepeatPicker: a ScrollView hands its content the IDEAL width,
                        // so rows shrink to their text unless told to fill (42013da7).
                        .frame(maxWidth: .infinity)
                }
                .navigationTitle(label)
                .navigationBarTitleDisplayMode(.inline)
                // Every picker sheet closes the same way (42013da7) — one word, same place.
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("actions.close", comment: "Close")) {
                            isEditing = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    @ViewBuilder private var editor: some View {
                VStack(spacing: PickerRowMetrics.sectionSpacing) {
                    // Quick options
                    VStack(spacing: PickerRowMetrics.rowSpacing) {
                        // "All day" is a CHOICE and belongs with the other quick picks, above
                        // Morning/Afternoon/Evening, in red as the one that removes the time
                        // (42013da7). It was a "Clear" button sat under the wheel.
                        Button {
                            clearTime()
                        } label: {
                            HStack {
                                Text(NSLocalizedString("picker.all_day", comment: "All day"))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(Theme.error)
                                Spacer()
                                if time == nil {
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

                        ForEach(quickOptions, id: \.1) { option in
                            Button {
                                setQuickTime(hour: option.1)
                                // Save immediately on quick option selection
                                saveTime()
                            } label: {
                                let isSelected = Calendar.current.component(.hour, from: selectedTime) == option.1
                                    && Calendar.current.component(.minute, from: selectedTime) == 0
                                HStack {
                                    Text(option.0)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, PickerRowMetrics.rowHorizontalPadding)
                                .padding(.vertical, PickerRowMetrics.rowVerticalPadding)
                                // The row has to FILL the sheet, or a VStack inside a ScrollView
                                // shrinks to its text and the list reads as a narrow column.
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Selected is tinted, not just ticked — a checkmark alone at the
                                // far edge of a full-width row is easy to miss (42013da7).
                                .background(isSelected ? Theme.accent.opacity(0.15)
                                                       : (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .stroke(isSelected ? Theme.accent : .clear, lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                    // Custom time picker - compact with hours, minutes, AM/PM
                    // No header, matching the date picker: a time wheel does not need a label
                    // telling you it is a time (42013da7).
                    VStack(alignment: .leading, spacing: PickerRowMetrics.rowSpacing) {
                        // The system time picker, not three 50pt-wide wheels clipped to 100pt
                        // (42013da7). Those were unreadably small, and the hour/minute/AM-PM
                        // triple had to be re-derived into `selectedTime` on every change —
                        // this edits the time directly. Minutes are no longer restricted to
                        // 5-minute steps either.
                        DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // "All day" moved up into the quick picks, so Set is the only action left.
                    // The styling goes on the LABEL, under .buttonStyle(.plain) — applied to the
                    // Button itself the default style tinted the text and drew its own background
                    // over the fill, which is what made these look wrong (42013da7).
                    Button {
                        saveTime()
                    } label: {
                        Text(NSLocalizedString("actions.set", comment: "Set"))
                            .bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing12)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                }
                .padding(compact ? 0 : Theme.spacing12)
                .background(compact ? Color.clear
                                    : (colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    @ViewBuilder private var trigger: some View {
                Button {
                    selectedTime = time ?? Date()
                    initializePickerValues()
                    isEditing = true
                } label: {
                    HStack(spacing: Theme.spacing4) {
                        if let time = time {
                            Text(formatTime(time))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .lineLimit(1)
                            if !compact { Spacer() }
                            if !compact {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                        } else if compact {
                            // All-day: a crossed-out clock, not the words "Add time" squeezed
                            // into a chip narrow enough to render as "Add…" (42013da7).
                            SlashedSymbol(systemName: "clock",
                                          color: colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                .accessibilityLabel(Text(NSLocalizedString("picker.add_time", comment: "")))
                        } else {
                            Text(NSLocalizedString("picker.add_time", comment: "Add time"))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    }
                    .padding(.horizontal, compact ? Theme.spacing8 : Theme.spacing12)
                    .padding(.vertical, compact ? Theme.spacing4 : Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
    }

    private func setQuickTime(hour: Int) {
        // CRITICAL: Use the correct base date
        // - If time binding is nil (all-day → timed): Use selectedTime (initialized from Date())
        // - If time binding exists (timed → timed): Use selectedTime (initialized from existing time)
        // selectedTime was already initialized correctly in line 164
        var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedTime)
        components.hour = hour
        components.minute = 0
        selectedTime = Calendar.current.date(from: components) ?? Date()
    }

    private func saveTime() {
        // Optimistic update: Update UI immediately - no blocking "smooth as butter"
        time = selectedTime
        isEditing = false

        // Haptic feedback for immediate response
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        // Capture onSave before entering detached task (Swift 6 concurrency fix)
        let saveAction = onSave

        // Fire-and-forget save in background
        _Concurrency.Task.detached {
            if let saveAction = saveAction {
                await saveAction()
            }
        }
    }

    private func clearTime() {
        // Optimistic update: Update UI immediately - no blocking "smooth as butter"
        time = nil
        isEditing = false

        // Haptic feedback for immediate response
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        // Capture onSave before entering detached task (Swift 6 concurrency fix)
        let saveAction = onSave

        // Fire-and-forget save in background
        _Concurrency.Task.detached {
            if let saveAction = saveAction {
                await saveAction()
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Initialize picker values from selectedTime
    private func initializePickerValues() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: selectedTime)

        let hour24 = components.hour ?? 9
        let minute = components.minute ?? 0

        // Convert 24-hour to 12-hour format
        if hour24 == 0 {
            pickerHour = 12
            pickerPeriod = 0 // AM
        } else if hour24 < 12 {
            pickerHour = hour24
            pickerPeriod = 0 // AM
        } else if hour24 == 12 {
            pickerHour = 12
            pickerPeriod = 1 // PM
        } else {
            pickerHour = hour24 - 12
            pickerPeriod = 1 // PM
        }

        // Round minute to nearest 5
        pickerMinute = (minute / 5) * 5
    }

    /// Update selectedTime from picker values
    private func updateSelectedTime() {
        // CRITICAL: Use the correct base date
        // selectedTime was already initialized correctly (Date() for all-day, existing time for timed)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedTime)

        // Convert 12-hour to 24-hour format
        var hour24 = pickerHour
        if pickerPeriod == 1 && pickerHour != 12 {
            hour24 += 12 // PM
        } else if pickerPeriod == 0 && pickerHour == 12 {
            hour24 = 0 // Midnight
        }

        components.hour = hour24
        components.minute = pickerMinute

        selectedTime = Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        InlineTimePicker(
            label: "Time",
            time: .constant(nil),
            onSave: nil
        )
        .padding()

        InlineTimePicker(
            label: "Time",
            time: .constant(Date()),
            onSave: nil
        )
        .padding()
    }
    .background(Theme.bgPrimary)
}
