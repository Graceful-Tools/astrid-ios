import SwiftUI

/// "+N" on the corner of an assignee's face, for a task several people share (AITD-466).
///
/// The leading control draws one face — the primary's — and its size is the row's tap target, so
/// the others are counted on its corner rather than stacked beside it. Draws nothing for a task
/// with one assignee, which is every task on a classic list.
struct AssigneeOverflowBadge: ViewModifier {
    let count: Int
    /// The side of the avatar being badged; the badge scales with it.
    let avatarSize: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if count > 0 {
                Text(verbatim: "+\(count)")
                    .font(.system(size: max(8, avatarSize * 0.32), weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, avatarSize * 0.1)
                    .padding(.vertical, avatarSize * 0.03)
                    .background(Capsule().fill(Theme.accent))
                    .overlay(Capsule().stroke(.white, lineWidth: 1))
                    .offset(x: avatarSize * 0.2, y: avatarSize * 0.15)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Counts the people assigned beyond the one whose face this view draws.
    func assigneeOverflowBadge(for task: Task, avatarSize: CGFloat) -> some View {
        modifier(AssigneeOverflowBadge(count: AssigneeResolver.additionalAssigneeCount(of: task),
                                       avatarSize: avatarSize))
    }
}
