import SwiftUI

/// Horizontal 4-button priority picker matching mobile web design
/// Displays: ○ (none), ! (low), !! (medium), !!! (high)
struct PriorityButtonPicker: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var priority: Task.Priority
    let onSave: ((Task.Priority) async throws -> Void)?
    /// Shows ONLY the selected priority; tap to change (Task 42013da7). Four 40pt buttons ate a
    /// whole row to display three options the task is not set to.
    var compact: Bool = false

    private let priorities: [Task.Priority] = [.none, .low, .medium, .high]

    var body: some View {
        if compact {
            Menu {
                ForEach(priorities, id: \.self) { level in
                    Button {
                        _Concurrency.Task { await handlePriorityChange(level) }
                    } label: {
                        // `systemImage: ""` renders as a MISSING image, which is why the menu
                        // came up blank. Only the selected row carries an image at all, and the
                        // priority's own symbol goes in the title so the menu reads like the
                        // chips it replaced.
                        if priority == level {
                            Label("\(level.symbol)  \(level.pickerTitle)", systemImage: "checkmark")
                        } else {
                            Text("\(level.symbol)  \(level.pickerTitle)")
                        }
                    }
                }
            } label: {
                Text(priority.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 30, minHeight: 28)
                    .foregroundColor(priority == .none ? priority.themeColor : .white)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .fill(priority == .none ? Color.clear : priority.themeColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .stroke(priority.themeColor, lineWidth: 1.5)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text(priority.pickerTitle))
        } else {
            HStack(spacing: Theme.spacing12) {
                ForEach(priorities, id: \.self) { priorityLevel in
                    PriorityButton(
                        priority: priorityLevel,
                        isSelected: priority == priorityLevel,
                        colorScheme: colorScheme
                    ) {
                        await handlePriorityChange(priorityLevel)
                    }
                }
            }
        }
    }

    private func handlePriorityChange(_ newPriority: Task.Priority) async {
        guard priority != newPriority else { return }

        // Optimistic update: Update UI immediately - no blocking "smooth as butter"
        let oldPriority = priority
        priority = newPriority

        // Haptic feedback for immediate response
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        // Capture onSave before entering detached task (Swift 6 concurrency fix)
        let saveAction = onSave

        // Fire-and-forget save in background - no isSaving state
        _Concurrency.Task.detached {
            do {
                if let saveAction = saveAction {
                    try await saveAction(newPriority)
                }
                // Success - priority already updated optimistically
            } catch {
                // Revert on failure
                await MainActor.run {
                    priority = oldPriority
                }
                print("❌ Failed to update priority: \(error)")
            }
        }
    }
}

/// Individual priority button
struct PriorityButton: View {
    let priority: Task.Priority
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () async -> Void

    var body: some View {
        Button {
            _Concurrency.Task {
                await action()
            }
        } label: {
            Text(priority.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundColor(isSelected ? .white : themeColor)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(isSelected ? themeColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(themeColor, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var themeColor: Color {
        switch priority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }
}

// MARK: - Extension for Priority Symbols

extension Task.Priority {
    /// Symbol matching mobile web design
    var symbol: String {
        switch self {
        case .none: return "○"   // Circle dot (U+25CB)
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    /// Spoken/menu name — the ! symbols are unreadable in a menu and to VoiceOver.
    var pickerTitle: String {
        switch self {
        case .none:   return NSLocalizedString("priority.none", comment: "")
        case .low:    return NSLocalizedString("priority.low", comment: "")
        case .medium: return NSLocalizedString("priority.medium", comment: "")
        case .high:   return NSLocalizedString("priority.high", comment: "")
        }
    }

    /// Theme color for the priority
    var themeColor: Color {
        switch self {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Priority")
                .font(Theme.Typography.caption1())
                .foregroundColor(Theme.textSecondary)

            PriorityButtonPicker(priority: .constant(.high), onSave: nil)
        }
        .padding()

        VStack(alignment: .leading, spacing: 8) {
            Text("All States")
                .font(Theme.Typography.caption1())
                .foregroundColor(Theme.textSecondary)

            VStack(spacing: 12) {
                PriorityButtonPicker(priority: .constant(.none), onSave: nil)
                PriorityButtonPicker(priority: .constant(.low), onSave: nil)
                PriorityButtonPicker(priority: .constant(.medium), onSave: nil)
                PriorityButtonPicker(priority: .constant(.high), onSave: nil)
            }
        }
        .padding()
    }
    .background(Theme.bgPrimary)
}
