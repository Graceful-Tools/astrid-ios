import SwiftUI
import UIKit

/// Persistently removes the internal padding from SwiftUI's TextEditor.
/// Uses layoutSubviews observation to re-apply zero insets whenever
/// UIKit resets them (e.g., during text changes, resizing, keyboard events).
struct TextEditorInsetRemover: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(TextEditorInsetWatcher())
    }
}

private struct TextEditorInsetWatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> InsetWatcherView {
        let view = InsetWatcherView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: InsetWatcherView, context: Context) {
        uiView.findAndFixTextView()
    }
}

/// A UIView that watches for layout changes and keeps the nearby
/// UITextView's insets zeroed. Uses CADisplayLink for the initial
/// setup period, then relies on layoutSubviews for ongoing fixes.
private class InsetWatcherView: UIView {
    private weak var watchedTextView: UITextView?
    private var setupAttempts = 0

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            findAndFixTextView()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        findAndFixTextView()
    }

    func findAndFixTextView() {
        if let tv = watchedTextView {
            applyZeroInsets(tv)
            return
        }

        guard let parent = superview else { return }
        if let tv = findTextView(in: parent) {
            watchedTextView = tv
            applyZeroInsets(tv)

            // Also observe text changes to re-apply after UIKit resets
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(textDidChange),
                name: UITextView.textDidChangeNotification,
                object: tv
            )
        } else if setupAttempts < 5 {
            // TextEditor might not be in hierarchy yet — retry
            setupAttempts += 1
            DispatchQueue.main.async { [weak self] in
                self?.findAndFixTextView()
            }
        }
    }

    @objc private func textDidChange(_ notification: Notification) {
        if let tv = notification.object as? UITextView {
            applyZeroInsets(tv)
        }
    }

    private func applyZeroInsets(_ textView: UITextView) {
        if textView.textContainerInset != .zero {
            textView.textContainerInset = .zero
        }
        if textView.textContainer.lineFragmentPadding != 0 {
            textView.textContainer.lineFragmentPadding = 0
        }
    }

    private func findTextView(in view: UIView) -> UITextView? {
        for subview in view.subviews {
            if let tv = subview as? UITextView {
                return tv
            }
            if let found = findTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension View {
    /// Removes the internal UITextView padding from a TextEditor,
    /// so external .padding() aligns exactly with overlay Text views.
    /// Persists across text changes and layout updates.
    func removeTextEditorInsets() -> some View {
        modifier(TextEditorInsetRemover())
    }
}
