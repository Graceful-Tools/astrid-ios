//  MacDropAction.swift
//  Astrid for Mac — whether dropping tasks onto a list MOVES or COPIES them (task 83f45d49).
//
//  macOS convention: a plain drag moves, Option-drag copies. Pure so the rule is testable without
//  a drag session.

#if os(macOS)
import AppKit

enum MacDropAction: Equatable {
    case move
    case copy

    /// Option held at drop time = copy, matching Finder and the rest of macOS.
    static func forModifiers(_ flags: NSEvent.ModifierFlags) -> MacDropAction {
        flags.contains(.option) ? .copy : .move
    }

    /// Read the CURRENT modifiers — drop handlers run outside an event, so the flags must be
    /// sampled at the moment of the drop rather than captured earlier.
    static var current: MacDropAction { forModifiers(NSEvent.modifierFlags) }
}
#endif
