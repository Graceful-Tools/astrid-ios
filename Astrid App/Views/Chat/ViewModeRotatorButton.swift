import SwiftUI

/// Single header button that rotates the task view-mode through the
/// available segments: list → messages → board → list. When the current
/// list has no project board attached, the rotation collapses to
/// list ↔ messages (skipping board).
///
/// Icon shows the *next* view the tap will switch to (a "play next"
/// affordance) so the button telegraphs what it does instead of what
/// you're already looking at.
///
/// Replaces the old 2-way ChatToggleButton with a 3-way rotator that
/// respects the unified-toggle logic from HeaderViewToggle.swift.
struct ViewModeRotatorButton: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var mode: HeaderToggleSegment
    let hasBoard: Bool
    /// False where list messages are a pane beside the list instead of a view that replaces it
    /// (iPad 2- and 3-column) — rotating there would hide the list to show what is already up.
    var includesMessages: Bool = true

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = next(after: mode)
            }
        } label: {
            Image(systemName: nextIcon)
                .font(Theme.Typography.headline())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                .accessibilityLabel(Text(accessibilityLabel))
        }
        .buttonStyle(.plain)
    }

    private func next(after current: HeaderToggleSegment) -> HeaderToggleSegment {
        nextRotatorSegment(after: current, hasBoard: hasBoard, includesMessages: includesMessages)
    }

    /// Icon for the segment the button will move to on tap.
    private var nextIcon: String {
        switch next(after: mode) {
        case .list:     return "list.bullet"
        case .messages: return "bubble.left.and.bubble.right"
        case .board:    return "rectangle.split.3x1"
        }
    }

    private var accessibilityLabel: String {
        switch next(after: mode) {
        case .list:     return "Switch to list view"
        case .messages: return "Switch to messages"
        case .board:    return "Switch to board view"
        }
    }
}
