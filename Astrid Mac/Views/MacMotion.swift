//  MacMotion.swift
//  Astrid for Mac — shared motion constants (Task 4c7b9f08) so state changes animate consistently
//  and subtly (native feel: 0.15–0.3s), instead of snapping.

#if os(macOS)
import SwiftUI

enum MacMotion {
    static let fastDuration: Double = 0.15      // hovers, small toggles
    static let mediumDuration: Double = 0.22    // rows, mode switches, theme cross-fade
    static let springResponse: Double = 0.28    // expand/collapse springs

    static var fast: Animation { .easeOut(duration: fastDuration) }
    static var medium: Animation { .easeInOut(duration: mediumDuration) }
    static var spring: Animation { .spring(response: springResponse, dampingFraction: 0.85) }
}
#endif
