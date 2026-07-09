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

    /// Adds a native leading-edge pan that can recognize alongside List row
    /// swipe/reorder recognizers. This makes opening the sidebar reliable even
    /// when SwiftUI's List claims the ordinary scroll pan first.
    func leadingEdgeSwipe(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        background(LeadingEdgeSwipeInstaller(isEnabled: isEnabled, action: action))
    }
}

private struct LeadingEdgeSwipeInstaller: UIViewControllerRepresentable {
    var isEnabled: Bool
    var action: () -> Void

    func makeUIViewController(context: Context) -> LeadingEdgeSwipeController {
        LeadingEdgeSwipeController(isEnabled: isEnabled, action: action)
    }

    func updateUIViewController(_ controller: LeadingEdgeSwipeController, context: Context) {
        controller.update(isEnabled: isEnabled, action: action)
    }

    static func dismantleUIViewController(_ controller: LeadingEdgeSwipeController, coordinator: Void) {
        controller.detachGesture()
    }
}

private final class LeadingEdgeSwipeController: UIViewController, UIGestureRecognizerDelegate {
    private var action: () -> Void
    private var requestedEnabled: Bool
    private weak var installedView: UIView?
    private lazy var edgeGesture: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeSwipe(_:)))
        gesture.edges = .left
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    init(isEnabled: Bool, action: @escaping () -> Void) {
        self.requestedEnabled = isEnabled
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installGestureIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installGestureIfNeeded()
    }

    func update(isEnabled: Bool, action: @escaping () -> Void) {
        requestedEnabled = isEnabled
        self.action = action
        edgeGesture.isEnabled = isEnabled
    }

    func detachGesture() {
        installedView?.removeGestureRecognizer(edgeGesture)
        installedView = nil
    }

    private func installGestureIfNeeded() {
        guard let target = navigationController?.view ?? view.window, target !== installedView else { return }
        detachGesture()
        target.addGestureRecognizer(edgeGesture)
        edgeGesture.isEnabled = requestedEnabled
        installedView = target
    }

    @objc private func handleEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: gesture.view).x
        let velocity = gesture.velocity(in: gesture.view).x
        if shouldTriggerLeadingEdgeSwipe(translationWidth: translation, velocityWidth: velocity) {
            action()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
