//  TaskCheckboxAsset.swift
//  The task checkbox, once for the phone and the Mac (ADEV-148), drawn from astrid-core's art
//  (ADEV-164).
//
//  The task row, the task detail, the Mac row, quick add and the quick changer's "Mark as done"
//  row all show this one box, so a task looks the same wherever you reach for it.
//
//  It used to be 32 fixed-colour PNGs (`check_box[_repeat][_checked]_<priority>`, 16 per app), in
//  the art's own blue, amber, red and grey: not the priority tokens, not a partner's brand, and
//  not Dark's lighter low priority (astrid-core register DS21). Now it is core's three vector
//  layers from the vendored `AstridDesign.xcassets` — `checkbox-box` or `checkbox-repeat` as a
//  template tinted with the palette's priority colour, then `checkbox-check` in its own green once
//  done — the same drawing web's `CheckboxArt` makes from the same source. A shape changes in
//  astrid-core and arrives by re-vendoring the catalog (`check:contracts` → design-art-vendored).

import SwiftUI

enum TaskCheckboxAsset {
    static let boxLayer = "checkbox-box"
    static let repeatLayer = "checkbox-repeat"
    static let checkLayer = "checkbox-check"

    /// The layers to draw, bottom first: the box, or the arrows for a repeating task, then the
    /// check once it is done.
    static func layers(completed: Bool, repeating: Bool) -> [String] {
        [repeating ? repeatLayer : boxLayer] + (completed ? [checkLayer] : [])
    }

    /// The box's colour: the palette's priority token (low is the accent, or its dark ink in
    /// Dark). No priority is the theme's muted text, as on web (`priority-text-none`):
    /// `priority-none` itself is 3:1 or less on Dark's card, and most tasks have no priority.
    static func tint(priority: Int, palette: AstridTokens.Palette) -> Color {
        switch priority {
        case 1: return palette.priorityLow
        case 2: return palette.priorityMedium
        case 3: return palette.priorityHigh
        default: return palette.textMuted
        }
    }

    /// The art's identity, `check_box[_repeat][_checked]_<priority>` — no longer an asset name,
    /// but still the checkbox's accessibility label, which is how the UI tests tell a ticked row
    /// from an open one (`TaskUITests`, `UITestLaunch.visibleRows`).
    static func name(priority: Int, completed: Bool, repeating: Bool) -> String {
        let safe = (0...3).contains(priority) ? priority : 0
        var name = "check_box"
        if repeating { name += "_repeat" }
        if completed { name += "_checked" }
        return name + "_\(safe)"
    }

    /// A task repeats unless its rule is nil or `.never`.
    static func isRepeating(_ repeating: Task.Repeating?) -> Bool {
        guard let repeating else { return false }
        return repeating != .never
    }
}

/// The checkbox art at `size`, in the current theme's priority colour.
struct TaskCheckboxArt: View {
    let priority: Int
    let completed: Bool
    let repeating: Bool
    var size: CGFloat = AstridTokens.Size.Comfortable.leadingControl

    @ThemedPalette private var palette

    var body: some View {
        ZStack {
            ForEach(TaskCheckboxAsset.layers(completed: completed, repeating: repeating), id: \.self) { layer in
                if layer == TaskCheckboxAsset.checkLayer {
                    Image(layer).resizable().renderingMode(.original)
                } else {
                    Image(layer).resizable().renderingMode(.template)
                        .foregroundStyle(TaskCheckboxAsset.tint(priority: priority, palette: palette))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TaskCheckboxAsset.name(priority: priority, completed: completed,
                                                                  repeating: repeating)))
    }
}
