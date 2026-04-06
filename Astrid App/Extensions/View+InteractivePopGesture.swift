import SwiftUI
import UIKit

/// Re-enables the interactive pop (swipe-back) gesture when the navigation bar
/// back button is hidden. SwiftUI disables the gesture when you use
/// `.navigationBarBackButtonHidden(true)`, but this modifier restores it.
struct InteractivePopGestureModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(InteractivePopGestureEnabler())
    }
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InteractivePopGestureController {
        InteractivePopGestureController()
    }

    func updateUIViewController(_ uiViewController: InteractivePopGestureController, context: Context) {}
}

/// A UIViewController that re-enables the interactive pop gesture on viewDidAppear.
/// This timing ensures the UINavigationController is available in the hierarchy.
final class InteractivePopGestureController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enablePopGesture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        enablePopGesture()
    }

    private func enablePopGesture() {
        guard let nav = navigationController else { return }
        nav.interactivePopGestureRecognizer?.isEnabled = true
        nav.interactivePopGestureRecognizer?.delegate = nil
    }
}

extension View {
    /// Enables swipe-back gesture even when the navigation bar back button is hidden
    func enableInteractivePopGesture() -> some View {
        modifier(InteractivePopGestureModifier())
    }
}
