//  MacTaskVisuals.swift
//  Astrid for Mac — shared task visual language mirroring iOS (Task: Mac UI mapping):
//  priority symbols/colors, the priority-ringed completion checkbox, and the 4-button priority
//  picker. Pure mappings are testable; the checkbox is drawn natively (green check in a
//  priority-colored rounded square) instead of shipping the iOS PNG set.

#if os(macOS)
import SwiftUI

enum MacTaskVisuals {
    /// Priority glyphs, matching iOS PriorityButton (○ / ! / !! / !!!).
    static func prioritySymbol(_ p: Task.Priority) -> String {
        switch p {
        case .none: return "○"
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    static func priorityLabel(_ p: Task.Priority) -> String {
        switch p {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Theme priority colors (none gray, low blue, medium amber, high red).
    static func priorityColor(_ p: Task.Priority) -> Color {
        switch p {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }

    static let allPriorities: [Task.Priority] = [.none, .low, .medium, .high]
}

/// Completion checkbox: a priority-colored rounded-square ring; a green check when complete
/// (mirrors the iOS check_box asset set, drawn natively).
struct MacTaskCheckbox: View {
    let completed: Bool
    let priority: Task.Priority
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28)
            .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: 2)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(completed ? Theme.success.opacity(0.12) : Color.clear)
            )
            .overlay {
                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.62, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Spring, not a linear fade: the check should pop in when the row DOES stay in place.
            .animation(MacMotion.spring, value: completed)
            .accessibilityLabel(completed ? "Completed" : "Not completed")
    }
}

/// 4-button priority picker mirroring iOS PriorityButtonPicker. Desktop-compact (0c1c83d4).
struct MacPriorityPicker: View {
    @Binding var selection: Task.Priority

    static let buttonWidth: CGFloat = 28
    static let buttonHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MacTaskVisuals.allPriorities, id: \.self) { p in
                let color = MacTaskVisuals.priorityColor(p)
                let isSelected = selection == p
                Button { selection = p } label: {
                    Text(MacTaskVisuals.prioritySymbol(p))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: Self.buttonWidth, height: Self.buttonHeight)
                        .foregroundStyle(isSelected ? .white : color)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .fill(isSelected ? color : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .stroke(color, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .macPointingHand()
                .help(MacTaskVisuals.priorityLabel(p))
            }
        }
    }
}
#endif
