//  MacScrollGeometry.swift
//  Astrid for Mac — vertical scroll observation that still builds on macOS 14.
//
//  `.onScrollGeometryChange(for:of:action:)` is macOS 15 / iOS 18 only. Calling it directly
//  pinned the whole Mac target's deployment floor to macOS 15, which meant Sonoma users could
//  download a DMG that refused to launch. The behaviour it drives — an intentional scroll
//  dismisses the detail pop-out (a1cb6083) — is a convenience, not a requirement: on macOS 14
//  the pop-out still closes by re-tapping the row or selecting another. So the modifier is
//  gated on availability and degrades to a no-op rather than dictating the supported OS range.

#if os(macOS)
import SwiftUI

extension View {
    /// Observe vertical content offset changes, where the platform supports it.
    /// The action receives (oldY, newY). On macOS 14 it is never called.
    @ViewBuilder
    func onVerticalScroll(_ action: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        if #available(macOS 15, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { oldY, newY in
                action(oldY, newY)
            }
        } else {
            self
        }
    }
}
#endif
