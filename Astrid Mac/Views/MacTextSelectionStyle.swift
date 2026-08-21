//  MacTextSelectionStyle.swift
//  Astrid for Mac — visible text selection for editable/readable task text.

#if os(macOS)
import SwiftUI
import AppKit

enum MacTextSelectionStyle {
    static var selectedTextAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.selectedTextColor,
            .backgroundColor: NSColor.selectedTextBackgroundColor,
        ]
    }
}

struct MacTextSelectionStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: view)
        }
    }

    private func apply(to view: NSView) {
        if let textView = view.window?.firstResponder as? NSTextView {
            textView.selectedTextAttributes = MacTextSelectionStyle.selectedTextAttributes
        }

        var next = view.superview
        while let current = next {
            if let textView = current as? NSTextView {
                textView.selectedTextAttributes = MacTextSelectionStyle.selectedTextAttributes
                return
            }
            next = current.superview
        }
    }
}

extension View {
    func macTextSelection() -> some View {
        background(MacTextSelectionStyler())
    }
}
#endif
