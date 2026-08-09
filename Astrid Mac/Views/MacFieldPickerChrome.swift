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
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDestructive ? Theme.error : Theme.accent)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// Scales its content and reserves the room the scaled result needs.
///
/// `scaleEffect` alone does not change layout, so a scaled calendar either
/// overlapped what sat below it or got clipped by a guessed frame. This measures
/// the natural size and reserves scale x that.
struct MacScaled<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder var content: Content

    @State private var natural: CGSize = .zero

    private struct SizeKey: PreferenceKey {
        static var defaultValue: CGSize { .zero }
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
    }

    var body: some View {
        content
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(SizeKey.self) { natural = $0 }
            .scaleEffect(scale)
            .frame(width: natural.width * scale, height: natural.height * scale)
    }
}

/// Sizes shared by the field popovers, so they read as one family.
enum MacFieldPicker {
    static var popoverWidth: CGFloat { 300 }
    static var narrowPopoverWidth: CGFloat { 210 }
    static var padding: CGFloat { 12 }
    static var rowSpacing: CGFloat { 5 }

    /// The graphical calendar is drawn at the system's own size, which is small
    /// for something you aim a pointer at. Scaled up rather than reproduced by
    /// hand. 1.9 overshot — big enough to crowd the popover — so it is eased back.
    static var calendarScale: CGFloat { 1.5 }
}
#endif
