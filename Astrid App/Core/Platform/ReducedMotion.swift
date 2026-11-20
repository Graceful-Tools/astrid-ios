//  ReducedMotion.swift
//  Astrid — the one place a spring or a pop is decided, so Reduce Motion is honoured on iOS and
//  Mac alike (AITD-624, design register DS17).
//
//  With Reduce Motion on, nothing springs, bounces or pops: a spring resolves to no animation,
//  so the state change lands at once. Short eases (hovers, cross-fades) are not motion in the
//  sense the setting means and keep animating. `scripts/check-source-contracts.mjs`
//  (`springs-honour-reduce-motion`) rejects a raw `.spring(` anywhere else in the app.

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ReducedMotion {
    /// The system's Reduce Motion setting, read at the moment of the call.
    static var isEnabled: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }

    /// A spring, or no animation at all when Reduce Motion is on.
    static func spring(response: Double = 0.5, dampingFraction: Double = 0.825,
                       reduceMotion: Bool = isEnabled) -> Animation? {
        reduceMotion ? nil : .spring(response: response, dampingFraction: dampingFraction)
    }

    /// The drawer / sidebar spring from the shared motion tokens.
    static func drawerSpring(reduceMotion: Bool = isEnabled) -> Animation? {
        spring(response: AstridTokens.Motion.drawerSpringDuration,
               dampingFraction: AstridTokens.Motion.drawerSpringDamping,
               reduceMotion: reduceMotion)
    }

    /// `motion.spring` — the ordinary state-change spring (expand, collapse, select). ADEV-163.
    static func standardSpring(reduceMotion: Bool = isEnabled) -> Animation? {
        spring(response: AstridTokens.Motion.springDuration,
               dampingFraction: AstridTokens.Motion.springDamping,
               reduceMotion: reduceMotion)
    }

    /// `motion.panel-spring` — a details panel opening beside the list.
    static func panelSpring(reduceMotion: Bool = isEnabled) -> Animation? {
        spring(response: AstridTokens.Motion.panelSpringDuration,
               dampingFraction: AstridTokens.Motion.panelSpringDamping,
               reduceMotion: reduceMotion)
    }

    /// `motion.hover` — a short ease, so it plays under Reduce Motion too (see above). ADEV-163.
    static var hover: Animation { .easeOut(duration: AstridTokens.Motion.hoverDuration) }

    /// Whether a decorative pop (a scale bump on tap) should play.
    static func allowsPop(reduceMotion: Bool = isEnabled) -> Bool { !reduceMotion }

    /// The checkbox pop's scale (`state.complete-pop-scale`, register DS16): iOS and Mac bump the
    /// control by the same amount on the tap that completes it. ADEV-163.
    static func popScale(_ popping: Bool) -> CGFloat {
        popping ? CGFloat(AstridTokens.State.completePopScale) : 1
    }
}
