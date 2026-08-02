import SwiftUI

/// Inline repeat pattern picker (matching mobile web)
struct InlineRepeatPicker: View {
    @Environment(\.colorScheme) var colorScheme

    let label: String
    @Binding var repeatPattern: Task.Repeating?
    @Binding var repeatFrom: Task.RepeatFromMode?
    @Binding var repeatingData: CustomRepeatingPattern?
    let onSave: (() async -> Void)?
    // Direct callback that passes values - avoids binding updates that cause view recreation crashes
    var onSaveCustom: ((Task.Repeating, Task.RepeatFromMode, CustomRepeatingPattern?) async -> Void)?
    var showLabel: Bool = true
    /// Sizes the trigger to its content so it can share the "When" row (Task 42013da7).
    var compact: Bool = false

    @State private var isEditing = false
    @State private var showingCustomEditor = false
    @State private var selectedPattern: Task.Repeating = .never
    @State private var selectedRepeatFrom: Task.RepeatFromMode = .COMPLETION_DATE
    @State private var tempRepeatingData: CustomRepeatingPattern?
    @State private var isSaving = false
    @State private var wasCancelled = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if showLabel {
                Text(label)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            if showingCustomEditor {
                // Custom repeating pattern editor (inline)
                CustomRepeatingPatternEditor(
                    pattern: Binding(
                        get: { tempRepeatingData ?? createDefaultPattern() },
                        set: { tempRepeatingData = $0 }
                    ),
                    repeatFrom: $selectedRepeatFrom,
                    onSave: {
                        saveCustomPattern()
                    },
                    onCancel: {
                        wasCancelled = true
                        showingCustomEditor = false
                        isEditing = true
                    }
                )
            } else if isEditing && !compact {
                editor
            } else {
                trigger
            }
        }
        // Compact triggers are chip-sized; the editor goes in a sheet so it gets the full width
        // the date picker's has always had (42013da7).
        .sheet(isPresented: Binding(get: { compact && isEditing && !showingCustomEditor },
                                    set: { isEditing = $0 })) {
            NavigationStack {
                ScrollView {
                    editor
                        .padding(Theme.spacing16)
                        // Without this the ScrollView hands the content its IDEAL width, which
                        // for a VStack of text rows is the widest word — the sheet was full
                        // width, the rows inside it were not (42013da7).
                        .frame(maxWidth: .infinity)
                }
                .navigationTitle(label)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: isEditing) { _, nowEditing in
            // Reset cancelled flag when opening
            if nowEditing {
                wasCancelled = false
            }
        }
        .onChange(of: showingCustomEditor) { wasShowing, nowShowing in
            // Auto-save custom pattern when editor closes (unless cancelled)
            if wasShowing && !nowShowing && !wasCancelled && !isSaving {
                // User closed custom editor without pressing Cancel - auto-save
                if tempRepeatingData != nil {
                    saveCustomPattern()
                }
            }
            // Reset cancelled flag when opening
            if nowShowing {
                wasCancelled = false
            }
        }
        .onDisappear {
            // Auto-save if view disappears while still editing (e.g., parent dismissed)
            if showingCustomEditor && !wasCancelled && !isSaving {
                if tempRepeatingData != nil {
                    saveCustomPattern()
                }
            }
        }
    }

    @ViewBuilder private var editor: some View {
                VStack(spacing: Theme.spacing12) {
                    // Preset options
                    VStack(spacing: Theme.spacing4) {
                        ForEach(Task.Repeating.allCases, id: \.self) { pattern in
                            Button {
                                if pattern == .custom {
                                    // Show custom editor
                                    tempRepeatingData = repeatingData ?? createDefaultPattern()
                                    showingCustomEditor = true
                                    isEditing = false
                                } else {
                                    // Save immediately for basic patterns (no confirmation needed)
                                    selectedPattern = pattern
                                    savePattern()
                                }
                            } label: {
                                let isSelected = selectedPattern == pattern
                                HStack {
                                    Text(pattern.displayName)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, Theme.spacing12)
                                .padding(.vertical, Theme.spacing12)
                                // Fill the sheet: a VStack inside a ScrollView otherwise shrinks
                                // to its widest word, which is why this never looked full width.
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Tinted, not just ticked — the checkmark alone at the far edge
                                // of a full-width row was easy to miss (42013da7).
                                .background(isSelected ? Theme.accent.opacity(0.15)
                                                       : (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .stroke(isSelected ? Theme.accent : .clear, lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Cancel button to dismiss without changes
                    Button("Cancel") {
                        wasCancelled = true
                        isEditing = false
                    }
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing8)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .padding(compact ? 0 : Theme.spacing12)
                .background(compact ? Color.clear
                                    : (colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    @ViewBuilder private var trigger: some View {
                Button {
                    selectedPattern = repeatPattern ?? .never
                    selectedRepeatFrom = repeatFrom ?? .COMPLETION_DATE
                    tempRepeatingData = repeatingData
                    isEditing = true
                } label: {
                    HStack(spacing: Theme.spacing4) {
                        if let pattern = repeatPattern, pattern != .never {
                            HStack(spacing: compact ? Theme.spacing4 : Theme.spacing8) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.accent)
                                // Compact drops the "(from due date)" qualifier — in a shared row
                                // it truncated the whole chip to "Ever…" (42013da7).
                                Text(compact ? pattern.displayName : getRepeatingSummary())
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    .lineLimit(compact ? 1 : 2)
                                    .fixedSize(horizontal: compact, vertical: false)
                            }
                        } else if compact {
                            // Not repeating: a crossed-out repeat symbol. Spelled out it needed a
                            // chip wide enough to truncate to "Ever…", which reads as nothing.
                            SlashedSymbol(systemName: "repeat",
                                          color: colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                .accessibilityLabel(Text(NSLocalizedString("repeating.no_repeat", comment: "")))
                        } else {
                            Text(NSLocalizedString("repeating.no_repeat", comment: "No repeat"))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                        if !compact {
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

    // MARK: - Helper Functions

    private func createDefaultPattern() -> CustomRepeatingPattern {
        return CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: 1,
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )
    }

    private func getRepeatingSummary() -> String {
        guard let pattern = repeatPattern else { return "No repeat" }

        if pattern == .custom, let data = repeatingData {
            return getCustomPatternSummary(data)
        }

        // Simple patterns
        var summary = pattern.displayName

        // Add repeat mode for simple patterns if DUE_DATE
        if pattern != .never && repeatFrom == .DUE_DATE {
            summary += " (from due date)"
        }

        return summary
    }

    /// Delegates to the SHARED summary so the picker and the task-detail row cannot word the
    /// same custom repeat differently (42013da7).
    private func getCustomPatternSummary(_ pattern: CustomRepeatingPattern) -> String {
        CustomRepeatSummary.text(for: pattern, repeatFrom: repeatFrom)
    }

    private func savePattern() {
        isSaving = true
        _Concurrency.Task {
            repeatPattern = selectedPattern == .never ? nil : selectedPattern

            // Simple patterns don't use repeatFrom or repeatingData
            if selectedPattern != .custom {
                repeatFrom = nil  // Clear repeat mode for simple patterns
                repeatingData = nil  // Clear custom data
            }

            if let onSave = onSave {
                await onSave()
            }
            isSaving = false
            isEditing = false
        }
    }

    private func saveCustomPattern() {
        // Capture values BEFORE dismissing the editor
        let patternToSave = tempRepeatingData
        let repeatFromToSave = selectedRepeatFrom

        // Dismiss the editor FIRST
        showingCustomEditor = false

        // Use direct callback if available - this avoids binding updates that can crash
        _Concurrency.Task { @MainActor in
            // Wait for UI to settle after dismissing editor
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

            if let onSaveCustom = onSaveCustom {
                // Direct callback - no binding updates needed
                await onSaveCustom(.custom, repeatFromToSave, patternToSave)
            } else {
                // Fallback to binding updates + onSave
                repeatPattern = .custom
                repeatFrom = repeatFromToSave
                repeatingData = patternToSave

                try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

                if let onSave = onSave {
                    await onSave()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        InlineRepeatPicker(
            label: "Repeat",
            repeatPattern: .constant(nil),
            repeatFrom: .constant(nil),
            repeatingData: .constant(nil),
            onSave: nil
        )
        .padding()

        InlineRepeatPicker(
            label: "Repeat",
            repeatPattern: .constant(.daily),
            repeatFrom: .constant(.COMPLETION_DATE),
            repeatingData: .constant(nil),
            onSave: nil
        )
        .padding()

        InlineRepeatPicker(
            label: "Repeat",
            repeatPattern: .constant(.custom),
            repeatFrom: .constant(.DUE_DATE),
            repeatingData: .constant(CustomRepeatingPattern(
                type: "custom",
                unit: "days",
                interval: 3,
                endCondition: "never",
                endAfterOccurrences: nil,
                endUntilDate: nil,
                weekdays: nil,
                monthRepeatType: nil,
                monthDay: nil,
                monthWeekday: nil,
                month: nil,
                day: nil
            )),
            onSave: nil
        )
        .padding()
    }
    .background(Theme.bgPrimary)
}
