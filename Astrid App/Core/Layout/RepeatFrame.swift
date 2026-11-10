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
    /// The iOS slot the row and the detail lay out — the same 34pt as the square, so a framed
    /// mark does not push its title out of line with the rows around it.
    static let footprint: CGFloat = 34
    /// The arrows are drawn this many times the leading control they replace ("for other users it
    /// should be larger") and overhang its slot. Web: 40px round a 32px square — the design token
    /// `size.repeat-frame-scale` (astrid-core `design/tokens.json`, register DS6). (AITD-606: iOS
    /// drew a fixed 40pt round its 34pt square, 1.18 ×, which Jon saw as the wrong size.)
    static let scale: CGFloat = 1.25
    /// The photo or "U" inside the loop, as a share of the control: web's 24px in a 32px square,
    /// which is also its 24-in-40 proportion of the frame.
    static let innerScale: CGFloat = 0.75

    /// The arrows' size round a leading control of `control` points.
    static func frameSize(control: CGFloat) -> CGFloat { control * scale }
    /// The photo or "U" inside the arrows round a leading control of `control` points.
    static func innerSize(control: CGFloat) -> CGFloat { control * innerScale }

    /// The same priority-coloured art the repeating checkbox uses.
    static func assetName(priority: Task.Priority) -> String {
        "check_box_repeat_\(priority.rawValue)"
    }
}
