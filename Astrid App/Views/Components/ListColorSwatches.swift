import SwiftUI

// Shared with the Mac target, like ListColorGlyph.

/// The list colour choices: the palette swatches plus a custom picker (AITD-500), as web's
/// ListColorSection draws them.
///
/// The colour is what identifies a list once hide_list_images removes its image, so this is the
/// setting that replaces the image picker rather than an extra. `ListColors` owns what may be
/// picked and stored; this only draws it.
struct ListColorSwatches: View {
    /// The list's stored colour.
    let color: String
    let onPick: (String) -> Void

    @Environment(\.self) private var environment
    /// What is drawn: the stored colour, or a custom pick still being dragged.
    @State private var shown: String
    @State private var pendingCustom: _Concurrency.Task<Void, Never>?

    /// The custom picker fires on every drag step, so it saves once the drag settles.
    private static let customSaveDelay: Duration = .milliseconds(400)
    private static let swatchSize: CGFloat = 28

    init(color: String, onPick: @escaping (String) -> Void) {
        self.color = color
        self.onPick = onPick
        _shown = State(initialValue: color)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ListColors.palette, id: \.self) { swatch in
                let isSelected = shown.lowercased() == swatch
                // .plain: a Form row with several default-style buttons fires all of them at once.
                Button {
                    pick(swatch)
                } label: {
                    Circle()
                        .fill(Color(hex: swatch) ?? Theme.accent)
                        .frame(width: Self.swatchSize, height: Self.swatchSize)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("listSettings.color.\(swatch)")
            }

            ColorPicker(NSLocalizedString("lists.custom_color", comment: ""),
                        selection: customSelection, supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(ListColors.isCustom(shown) ? .isSelected : [])
                .accessibilityIdentifier("listSettings.color.custom")
        }
        // Follow a change made elsewhere — another device, or the save being refused.
        .onChange(of: color) { _, stored in
            shown = stored
        }
        // Closing the sheet inside the delay must not lose the pick.
        .onDisappear {
            guard pendingCustom != nil else { return }
            pendingCustom?.cancel()
            pendingCustom = nil
            onPick(shown)
        }
    }

    private var customSelection: Binding<Color> {
        Binding(
            get: { Color(hex: shown) ?? Theme.accent },
            set: { picked in
                let resolved = picked.resolve(in: environment)
                previewCustom(ListColors.hex(red: Double(resolved.red), green: Double(resolved.green),
                                             blue: Double(resolved.blue)))
            }
        )
    }

    private func pick(_ swatch: String) {
        pendingCustom?.cancel()
        pendingCustom = nil
        shown = swatch
        onPick(swatch)
    }

    private func previewCustom(_ hex: String) {
        guard hex != shown.lowercased() else { return }
        shown = hex
        pendingCustom?.cancel()
        pendingCustom = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: Self.customSaveDelay)
            guard !_Concurrency.Task.isCancelled else { return }
            pendingCustom = nil
            onPick(hex)
        }
    }
}
