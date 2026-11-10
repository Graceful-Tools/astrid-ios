//  MacMotion.swift
//  Astrid for Mac — shared motion constants (Task 4c7b9f08) so state changes animate consistently
//  and subtly (native feel: 0.15–0.3s), instead of snapping.

#if os(macOS)
import SwiftUI

//  The values are astrid-core's motion tokens (AITD-610), so web, iOS and Mac move alike.
enum MacMotion {
    static let fastDuration = AstridTokens.Motion.fastDuration       // hovers, small toggles
    static let mediumDuration = AstridTokens.Motion.mediumDuration   // rows, mode switches, theme cross-fade
    static let springResponse = AstridTokens.Motion.springDuration   // expand/collapse springs
    static let springDamping = AstridTokens.Motion.springDamping

    static var fast: Animation { .easeOut(duration: fastDuration) }
    static var medium: Animation { .easeInOut(duration: mediumDuration) }
    static var spring: Animation { .spring(response: springResponse, dampingFraction: springDamping) }
}
#endif
