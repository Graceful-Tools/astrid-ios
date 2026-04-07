import SwiftUI

/// A responsive swipe-to-dismiss gesture modifier
/// Works from anywhere on the screen, not just the edge
struct SwipeToDismissModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    var customAction: (() -> Void)?

    // Thresholds for dismissal
    private let dismissThreshold: CGFloat = 50
    private let velocityThreshold: CGFloat = 300

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        let velocity = value.velocity.width

                        // Check if swipe is primarily horizontal and rightward
                        guard horizontalAmount > 0 && horizontalAmount > verticalAmount else {
                            return
                        }

                        // Dismiss if threshold reached or velocity is high enough
                        if horizontalAmount > dismissThreshold || velocity > velocityThreshold {
                            if let customAction {
                                customAction()
                            } else {
                                dismiss()
                            }
                        }
                    }
            )
    }
}

extension View {
    /// Adds a responsive swipe-to-dismiss gesture that works from anywhere on the screen
    func swipeToDismiss() -> some View {
        modifier(SwipeToDismissModifier())
    }

    /// Adds a responsive swipe-to-dismiss gesture with a custom action instead of dismiss()
    func swipeToDismiss(action: @escaping () -> Void) -> some View {
        modifier(SwipeToDismissModifier(customAction: action))
    }
}
