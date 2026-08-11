//  MacRepeatPicker.swift
//  Astrid for Mac — the repeat control, built like every other field control.
//
//  It used to be a borderless `Menu`. AppKit draws menu items in the system's
//  own style, so it looked and behaved unlike the date and time chips sitting
//  beside it — three controls on one row, two of one kind and one of another.
//  And choosing "Custom" opened a centred SHEET that took over the window,
//  which is a different interaction again for the same act of picking a value.
//
//  Now: the same chip, the same popover, the same choice rows — and the custom
//  editor opens in that popover rather than seizing the window.

#if os(macOS)
import SwiftUI

struct MacRepeatPicker: View {
    @Binding var repeating: Task.Repeating
    @Binding var customPattern: CustomRepeatingPattern?
    /// Persist a non-custom choice, or a custom pattern once edited.
    let onCommit: () -> Void

    @State private var isPresented = false
    @State private var showingCustomEditor = false

    /// A task that does not repeat has nothing to say, so it says nothing: just
    /// the glyph. Printing "One time only" spends a chip's width announcing the
    /// default, and on a narrow panel that is enough to force the row to wrap.
    private var isSilent: Bool { repeating == .never }

    private var label: String {
        if repeating == .custom, let customPattern {
            return MacCustomRepeat.summary(customPattern)
        }
        return repeating.displayName
    }

    var body: some View {
        Button { isPresented = true } label: {
            if isSilent {
                MacFieldGlyphTrigger(systemImage: "repeat",
                                     accessibilityLabel: NSLocalizedString("repeating.title",
                                                                           comment: "Repeat"))
            } else {
                // A custom repeat shows its actual pattern ("Every 2 weeks"), not
                // the word "Custom". The pattern used to live on a line of its own
                // below the row, which meant one value occupying two elements —
                // and, before that, a third: a separate "Edit" button beside it.
                MacFieldTrigger(text: label, systemImage: "repeat")
            }
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .help(NSLocalizedString("repeating.title", comment: "Repeat"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            if showingCustomEditor {
                // In the popover, not a window-sized sheet: picking a repeat is
                // one interaction, so it stays in one place.
                MacCustomRepeatEditor(initial: customPattern) { pattern in
                    customPattern = pattern
                    repeating = .custom
                    showingCustomEditor = false
                    isPresented = false
                    onCommit()
                }
            } else {
                options
            }
        }
        .onChange(of: isPresented) { _, shown in
            // Reopening should land on the list, not wherever it was left.
            if !shown { showingCustomEditor = false }
        }
    }

    private var options: some View {
        VStack(alignment: .center, spacing: MacFieldPicker.rowSpacing) {
            ForEach(Task.Repeating.allCases, id: \.self) { option in
                MacPickerRow(title: option.displayName,
                             isChecked: option == repeating) {
                    if option == .custom {
                        showingCustomEditor = true
                    } else {
                        repeating = option
                        customPattern = nil
                        isPresented = false
                        onCommit()
                    }
                }
            }
        }
        .padding(MacFieldPicker.padding)
        .frame(width: MacFieldPicker.narrowPopoverWidth)
    }
}
#endif
