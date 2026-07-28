//  MacTaskVisuals.swift
//  Astrid for Mac — shared task visual language mirroring iOS (Task: Mac UI mapping):
//  priority symbols/colors, the priority-ringed completion checkbox, and the 4-button priority
//  picker. Pure mappings are testable; the checkbox is drawn natively (green check in a
//  priority-colored rounded square) instead of shipping the iOS PNG set.

#if os(macOS)
import SwiftUI

enum MacTaskVisuals {
    // Checkbox proportions. iOS draws its checkbox from a designed ASSET (check_box_checked_*)
    // where the mark fills most of the box; Mac draws it from a shape + SF Symbol, and at 0.62 the
    // mark read small inside a chunky 2pt box (task: "checkbox size should be smaller relative to
    // checkmark"). The mark now takes most of the box, and the stroke scales with the size rather
    // than staying 2pt at every size.
    /// Checkbox sizes. 20/22 read chunky next to macOS's 13pt body text — the box should sit with
    /// the type, not dominate the row.
    static let rowCheckboxSize: CGFloat = 17
    static let detailCheckboxSize: CGFloat = 19

    static let checkmarkRatio: CGFloat = 0.78
    static let checkboxCornerRatio: CGFloat = 0.28
    static func checkboxStroke(size: CGFloat) -> CGFloat { max(1.5, size * 0.075) }

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
    /// Repeating tasks get the arrow-cornered box iOS and web show (ca13c94b).
    var repeating: Bool = false

    var body: some View {
        // The shared artwork first, so all three platforms show the same checkbox; the drawn shape
        // below stays as a fallback for a missing asset rather than rendering nothing.
        if let image = NSImage(named: MacCheckboxAsset.name(priority: priority.rawValue,
                                                            completed: completed,
                                                            repeating: repeating)) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .animation(MacMotion.spring, value: completed)
                .accessibilityLabel(completed ? "Completed" : "Not completed")
        } else {
            drawnFallback
        }
    }

    private var drawnFallback: some View {
        RoundedRectangle(cornerRadius: size * MacTaskVisuals.checkboxCornerRatio)
            .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: MacTaskVisuals.checkboxStroke(size: size))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * MacTaskVisuals.checkboxCornerRatio)
                    .fill(completed ? Theme.success.opacity(0.12) : Color.clear)
            )
            .overlay {
                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * MacTaskVisuals.checkmarkRatio, weight: .bold))
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
