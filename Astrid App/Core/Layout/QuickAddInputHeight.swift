import Combine
import CoreGraphics
import Foundation

/// How tall the quick-add task input is allowed to grow.
///
/// It used to be a hardcoded 200pt, so a long title stopped growing at roughly
/// eight lines and started scrolling inside itself while most of the screen sat
/// empty. The ceiling should be the room that actually exists.

/// The tallest the quick-add text input may become: everything between the top
/// safe area and the top of the keyboard, less the bar's own chrome.
///
/// `keyboardTopY` is the keyboard's top edge in screen coordinates, which is
/// the screen height when no keyboard is up — so a dismissal widens the ceiling
/// with no special case. Keyboard notifications can report an off-screen frame
/// mid-animation, hence the floor: the field must stay usable at one line
/// whatever geometry arrives.
func quickAddMaxInputHeight(keyboardTopY: CGFloat,
                            topSafeAreaInset: CGFloat,
                            barChromeHeight: CGFloat,
                            minHeight: CGFloat) -> CGFloat {
    let available = keyboardTopY - topSafeAreaInset - barChromeHeight
    guard available.isFinite else { return minHeight }
    return max(minHeight, available)
}

#if canImport(UIKit)
import UIKit

/// Publishes the top edge of the keyboard in screen coordinates, plus the top
/// safe-area inset — the two live inputs `quickAddMaxInputHeight` needs.
///
/// A shared singleton: every board column renders its own quick-add footer, and
/// one observer for the app is cheaper than one per column.
///
/// iOS only. The shared `Core/` tree compiles into the Mac target too, and the
/// Mac quick-add has no software keyboard to avoid.
@MainActor
final class KeyboardLayoutObserver: ObservableObject {
    static let shared = KeyboardLayoutObserver()

    /// Screen-space y of the keyboard's top edge. Defaults to the screen height
    /// (no keyboard), which is also what it returns to on dismissal.
    @Published private(set) var keyboardTopY: CGFloat
    @Published private(set) var topSafeAreaInset: CGFloat

    private var observers: [NSObjectProtocol] = []

    private init() {
        keyboardTopY = KeyboardLayoutObserver.currentScreenHeight
        topSafeAreaInset = KeyboardLayoutObserver.currentTopSafeAreaInset

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
                .cgRectValue
            MainActor.assumeIsolated {
                self?.apply(keyboardFrame: frame)
            }
        })
        observers.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.apply(keyboardFrame: nil)
            }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static var currentScreenHeight: CGFloat {
        activeScene?.screen.bounds.height ?? UIScreen.main.bounds.height
    }

    private static var currentTopSafeAreaInset: CGFloat {
        activeScene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    /// A nil frame means "no keyboard". A frame parked off the bottom of the
    /// screen — a dismissal, or the floating iPad keyboard mid-move — means the
    /// same thing, so it is clamped to the screen height rather than special-cased.
    private func apply(keyboardFrame: CGRect?) {
        topSafeAreaInset = KeyboardLayoutObserver.currentTopSafeAreaInset
        let screenHeight = KeyboardLayoutObserver.currentScreenHeight
        guard let keyboardFrame else {
            keyboardTopY = screenHeight
            return
        }
        keyboardTopY = min(keyboardFrame.minY, screenHeight)
    }
}
#endif
