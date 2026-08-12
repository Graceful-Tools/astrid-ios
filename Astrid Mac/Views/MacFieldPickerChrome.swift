//  MacFieldPickerChrome.swift
//  Astrid for Mac — ONE way a field control looks and behaves.
//
//  Every editable field in the task detail is the same idea: a chip showing the
//  current value, which opens a popover of choices. It had been built three
//  different ways — the date and time as chips with popovers, the repeat as a
//  borderless `Menu` drawn in the system's own style, and the custom-repeat
//  editor as a centred sheet that takes over the window. Three patterns for one
//  interaction, which is what makes the panel feel assembled rather than
//  designed.
//
//  So the trigger and the choice row live here, once, and every field uses them.

#if os(macOS)
import SwiftUI

/// The chip that shows a field's current value and opens its popover.
struct MacFieldTrigger: View {
    let text: String
    /// nil draws no glyph — the usual case. The row already leads with an icon
    /// naming the field, so repeating it inside the chip says the same thing
    /// twice on one line.
    var systemImage: String? = nil
    /// Muted when the control has no value: a prompt, not data.
    var isPlaceholder: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
            Text(text)
                .font(.system(size: 11))
                // NOT lineLimit(1): a truncated date is not a date. "Sat, Aug 15,…"
                // told you less than the bare date it replaced. The chip sizes to
                // its content and the ROW wraps instead (FlowLayout).
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isPlaceholder ? Theme.textMuted : Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A glyph-only trigger, for a field whose value is "nothing to say".
///
/// A task that does not repeat should not spend a chip's width on the words
/// "One time only" — that is the default, and printing it pushes the row into
/// wrapping to announce that nothing is happening.
struct MacFieldGlyphTrigger: View {
    let systemImage: String
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(accessibilityLabel)
    }
}

/// One selectable row inside a field's popover.
///
/// Outlined, not bare text: a column of choices with no borders reads as a list
/// of labels with no indication that any of it is clickable.
struct MacPickerRow: View {
    let title: String
    var isDestructive: Bool = false
    var isChecked: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    private var tint: Color { isDestructive ? Theme.error : Theme.textPrimary }

    var body: some View {
        Button(action: action) {
            // Centred, with the checkmark OVERLAID at the trailing edge rather than taking part
            // in the layout (task d4f663a3). In an HStack the tick pushes the title off-centre,
            // so "Today" and "Today ✓" would sit at different places in the same column.
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                // Room for the tick on BOTH sides, so reserving it does not shift the centre.
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(alignment: .trailing) {
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isDestructive ? Theme.error : Theme.accent)
                            .padding(.trailing, 9)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Theme.accent.opacity(0.10) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isChecked ? (isDestructive ? Theme.error : Theme.accent)
                                                : Theme.border,
                                      lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .onHover { isHovering = $0 }
    }
}

/// How much room a scaled child needs. Pure, so the rule can be tested without a view.
enum MacScaledLayout {
    /// Scale from the TOP, not the centre. Centre-anchored scaling sends any overflow
    /// BOTH ways, which is how a calendar ends up drawn over the buttons above it
    /// (task 010a7826); anchored to the top, overflow can only go downward.
    static let anchor: UnitPoint = .top

    /// The room to reserve for a child of natural size `natural` drawn at `scale`.
    ///
    /// An unmeasured axis falls back to an estimate rather than to ZERO. Zero is the
    /// dangerous answer: a popover sizes itself on the first layout pass, and on that pass
    /// the measurement has not arrived yet — so it would build itself too short and the
    /// scaled content would draw outside its bounds, over its neighbours. Each axis falls
    /// back independently, since one can be measured before the other.
    static func reserved(natural: CGSize, scale: CGFloat, fallback: CGSize) -> CGSize {
        CGSize(width: (natural.width > 0 ? natural.width : fallback.width) * scale,
               height: (natural.height > 0 ? natural.height : fallback.height) * scale)
    }
}

/// Scales its content and reserves the room the scaled result needs.
///
/// `scaleEffect` alone does not change layout, so a scaled calendar either overlapped what
/// sat around it or got clipped by a guessed frame. This measures the natural size and
/// reserves scale x that — falling back to an estimate until the measurement lands, because
/// reserving zero for even one pass is what put the calendar on top of the buttons.
struct MacScaled<Content: View>: View {
    let scale: CGFloat
    /// Used until the child has been measured. Only the first layout pass sees it.
    var fallback: CGSize = MacFieldPicker.calendarNaturalEstimate
    /// The room this view ends up occupying, reported as it changes — so a popover can size
    /// itself to the scaled content instead of guessing a width for it (task d4f663a3).
    var onReserve: ((CGSize) -> Void)? = nil
    @ViewBuilder var content: Content

    @State private var natural: CGSize = .zero

    private struct SizeKey: PreferenceKey {
        static var defaultValue: CGSize { .zero }
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }

    var body: some View {
        let reserved = MacScaledLayout.reserved(natural: natural, scale: scale, fallback: fallback)
        return content
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(SizeKey.self) { measured in
                natural = measured
                onReserve?(MacScaledLayout.reserved(natural: measured, scale: scale, fallback: fallback))
            }
            .scaleEffect(scale, anchor: MacScaledLayout.anchor)
            .frame(width: reserved.width, height: reserved.height, alignment: .top)
    }
}

/// Sizes shared by the field popovers, so they read as one family.
enum MacFieldPicker {
    static var narrowPopoverWidth: CGFloat { 210 }
    static var padding: CGFloat { 12 }
    static var rowSpacing: CGFloat { 5 }

    /// The width of a popover built around a calendar `calendarWidth` wide (already scaled).
    ///
    /// The date popover used to be a hand-picked 300. AppKit draws the graphical calendar at
    /// 139pt, so at 1.5x it spans 208.5 of a 276pt content box and floats there with ~34pt of
    /// dead space down each side (task d4f663a3). The popover follows the calendar instead.
    ///
    /// The floor is the width of the other field popovers: shrinking to a small calendar would
    /// squeeze the choice rows, and the family should not look like three different widths.
    static func popoverWidth(forCalendarWidth calendarWidth: CGFloat) -> CGFloat {
        max(narrowPopoverWidth, calendarWidth + padding * 2)
    }

    /// The graphical calendar is drawn at the system's own size, which is small
    /// for something you aim a pointer at. Scaled up rather than reproduced by
    /// hand. 1.9 overshot — big enough to crowd the popover — so it is eased back.
    static var calendarScale: CGFloat { 1.5 }

    /// What the graphical DatePicker measures before scaling. Used for the first layout pass,
    /// before the real measurement arrives — and the popover's width is built from it, so being
    /// wrong is a visible jump as the measurement lands. It was a guess of 180x190; AppKit
    /// actually draws 139x148, which MacFieldPickerLayoutTests re-measures rather than trusts.
    static var calendarNaturalEstimate: CGSize { CGSize(width: 139, height: 148) }
}
#endif
