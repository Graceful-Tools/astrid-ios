//  RepeatFrame.swift
//  The repeat arrows as the border of someone else's photo or the "U" mark. (AITD-602)
//
//  Your own repeating task has always swapped its checkbox for the arrows (`check_box_repeat_<p>`).
//  A repeating task assigned to someone else, or to nobody, drew the plain priority square, so
//  "this repeats" was visible on one of the three marks only. Jon: "make the checkbox border
//  around faces and unassigned the rotating arrow just like assigned to you … for other users it
//  should be larger and the border around the profile photo." Web shipped the same in AWTD-1571
//  (`RepeatFrame` in `components/task-leading-control.tsx`): a 24px round photo in a 40px loop.
//
//  The rule and the numbers live here, not in a view, so the row and the detail cannot draw it
//  two ways and a test can reach both.

import CoreGraphics

extension TaskLeadingControl {

    /// Whether this mark is drawn inside the repeat arrows rather than the plain square.
    ///
    /// Never the checkbox: for your own task the checkbox already IS the arrows, and framing it
    /// would draw them twice.
    static func showsRepeatFrame(kind: TaskLeadingControl, repeating: Task.Repeating?) -> Bool {
        guard let repeating, repeating != .never else { return false }
        switch kind {
        case .checkbox: return false
        case .avatar, .unassigned: return true
        }
    }
}

enum RepeatFrameGeometry {
    /// The slot the row and the detail lay out — the same 34pt as the square, so a framed mark
    /// does not push its title out of line with the rows around it.
    static let footprint: CGFloat = 34
    /// The arrows, drawn larger than the square ("for other users it should be larger") and
    /// allowed to overhang the slot by 3pt a side.
    static let frameSize: CGFloat = 40
    /// The photo or "U" inside the loop — web's 24-in-40 proportion.
    static let innerSize: CGFloat = 24

    /// The same priority-coloured art the repeating checkbox uses.
    static func assetName(priority: Task.Priority) -> String {
        "check_box_repeat_\(priority.rawValue)"
    }
}
