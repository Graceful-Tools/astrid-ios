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

    /// Whether a decorative pop (a scale bump on tap) should play.
    static func allowsPop(reduceMotion: Bool = isEnabled) -> Bool { !reduceMotion }
}
