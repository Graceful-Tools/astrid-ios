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

    // Quick time options (matching mobile web)
    private let quickOptions: [(String, Int)] = [
        ("Morning (9 AM)", 9),
        ("Afternoon (2 PM)", 14),
        ("Evening (6 PM)", 18),
        ("Night (9 PM)", 21)
    ]

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
                ScrollView { editor.padding(Theme.spacing16) }
                    .navigationTitle(label)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder private var editor: some View {
                VStack(spacing: Theme.spacing12) {
                    // Quick options
                    VStack(spacing: Theme.spacing4) {
                        ForEach(quickOptions, id: \.1) { option in
                            Button {
                                setQuickTime(hour: option.1)
                                // Save immediately on quick option selection
                                saveTime()
                            } label: {
                                HStack {
                                    Text(option.0)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Spacer()
                                    if Calendar.current.component(.hour, from: selectedTime) == option.1 &&
                                       Calendar.current.component(.minute, from: selectedTime) == 0 {
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

                    Divider()
                        .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                    // Custom time picker - compact with hours, minutes, AM/PM
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        Text(NSLocalizedString("picker.custom_time", comment: "Custom Time"))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                        // Compact time picker with reduced font size
                        HStack(spacing: 4) {
                            // Hour picker (1-12)
                            Picker("Hour", selection: $pickerHour) {
                                ForEach(1...12, id: \.self) { hour in
                                    Text("\(hour)")
                                        .font(.system(size: 16))
                                        .tag(hour)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 50)
                            .clipped()

                            Text(":")
                                .font(.system(size: 16, weight: .medium))

                            // Minute picker (00-59, step by 5)
                            Picker("Minute", selection: $pickerMinute) {
                                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                    Text(String(format: "%02d", minute))
                                        .font(.system(size: 16))
                                        .tag(minute)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 50)
                            .clipped()

                            // AM/PM picker
                            Picker("Period", selection: $pickerPeriod) {
                                Text("AM").font(.system(size: 16)).tag(0)
                                Text("PM").font(.system(size: 16)).tag(1)
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 50)
                            .clipped()
                        }
                        .frame(height: 100)
                        .onChange(of: pickerHour) { _, _ in updateSelectedTime() }
                        .onChange(of: pickerMinute) { _, _ in updateSelectedTime() }
                        .onChange(of: pickerPeriod) { _, _ in updateSelectedTime() }
                    }

                    // Actions
                    HStack(spacing: Theme.spacing12) {
                        Button("Clear") {
                            clearTime()
                        }
                        .foregroundColor(Theme.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing8)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                        Button("Set") {
                            saveTime()
                        }
                        .bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing8)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
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
