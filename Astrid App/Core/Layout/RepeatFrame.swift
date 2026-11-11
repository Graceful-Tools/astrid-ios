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
    /// The arrows border the mark at the size of the leading control they replace, so a repeating
    /// row's mark is no bigger than the plain squares beside it (AITD-612). AITD-606 had them
    /// 1.25 × and overhanging the slot. Design token `size.repeat-frame-scale`.
    static let scale: CGFloat = 1.0
    /// The photo or "U" inside the arrows, as a share of the control — the WHOLE square, the same
    /// size as a non-repeating task's photo (AITD-612 reopened, Jon 2026-11-11: "Still see smaller
    /// checkbox for repeating tasks … The same size as the default profile photo"). It was 0.625
    /// (web's 20px in 32px), which left a 21pt face beside 34pt ones. Token
    /// `size.repeat-frame-inner-scale`.
    static let innerScale: CGFloat = 1.0
    /// The rounded square the photo is clipped to and the arrows follow — the non-repeating
    /// photo's 8pt corner at 34pt.
    static let cornerScale: CGFloat = 8.0 / 34.0
    /// Each arrowhead's length along its edge, and half its width across it, as shares of the
    /// control. The arrows are drawn as the border rather than as the 56px bitmap round the
    /// photo, whose loop only has room for half the square inside it.
    static let headLength: CGFloat = 0.16
    static let headHalfWidth: CGFloat = 0.13
    /// The brackets' stroke — the plain square's 2pt priority outline.
    static let lineWidth: CGFloat = 2

    /// The arrows' size round a leading control of `control` points.
    static func frameSize(control: CGFloat) -> CGFloat { control * scale }
    /// The photo or "U" inside the arrows round a leading control of `control` points.
    static func innerSize(control: CGFloat) -> CGFloat { control * innerScale }
    /// The corner radius of the photo's rounded square and of the arrows that border it.
    static func cornerRadius(control: CGFloat) -> CGFloat { control * cornerScale }
}
