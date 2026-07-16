//  MacKeyMonitor.swift
//  Astrid for Mac — map a physical key event to the shared KeyboardShortcuts key string
//  (Task cdfbd79f). Pure/testable: arrow + delete keys use keyCodes; everything else uses
//  the produced character, lowercased.

#if os(macOS)
import Foundation

enum MacKeyMonitor {
    // Carbon virtual key codes for the keys the shared table addresses specially.
    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124
    private static let downArrow: UInt16 = 125
    private static let upArrow: UInt16 = 126
    private static let backspace: UInt16 = 51
    private static let forwardDelete: UInt16 = 117

    /// Normalize an event to a KeyboardShortcuts.all key token, or nil if not usable.
    static func normalizedKey(chars: String?, keyCode: UInt16) -> String? {
        switch keyCode {
        case leftArrow:  return "←"
        case rightArrow: return "→"
        case downArrow:  return "↓"
        case upArrow:    return "↑"
        case backspace:  return "Backspace"
        case forwardDelete: return "Delete"
        default: break
        }
        guard let chars, !chars.isEmpty else { return nil }
        // Single printable character (letters, digits, "?") — lowercase for table lookup.
        return chars.lowercased()
    }
}
#endif
