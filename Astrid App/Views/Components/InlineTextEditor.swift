import SwiftUI

/// Inline text editor that appears as text until tapped, then becomes editable
struct InlineTextEditor: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var onSave: (() -> Void)?

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            Text(label)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

            if isEditing {
                TextField(placeholder, text: $text)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing {
                            isEditing = false
                            onSave?()
                        }
                    }
                    .onSubmit {
                        isEditing = false
                        onSave?()
                    }
            } else {
                Text(text.isEmpty ? placeholder : text)
                    .font(Theme.Typography.body())
                    .foregroundColor(text.isEmpty
                        ? (colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        : (colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .onTapGesture {
                        isEditing = true
                        isFocused = true
                    }
            }
        }
    }
}

/// Layout metrics that keep `InlineTextAreaEditor`'s placeholder aligned with
/// the caret.
///
/// SwiftUI's `TextEditor` is backed by a `UITextView` whose text container
/// adds its own insets *inside* any SwiftUI `.padding(...)`: a default
/// `lineFragmentPadding` of 5pt horizontally and a `textContainerInset` of
/// 8pt vertically. Glyphs and the caret render at `containerPadding + inset`,
/// so a plain `Text` placeholder given the same `.padding(...)` lands at
/// `containerPadding` only — leaving the placeholder and caret out of sync.
/// The placeholder uses `placeholder*Padding` to sit on the real text origin.
enum InlineTextAreaMetrics {
    /// SwiftUI padding applied around the TextEditor and placeholder.
    static let containerPadding: CGFloat = 12

    /// `UITextView.textContainer.lineFragmentPadding` default.
    static let textViewHorizontalInset: CGFloat = 5
    /// `UITextView.textContainerInset` default top/bottom.
    static let textViewVerticalInset: CGFloat = 8

    /// Where the TextEditor renders glyphs and the caret, measured from the
    /// editor container's top-leading corner.
    static let textOriginLeading = containerPadding + textViewHorizontalInset
    static let textOriginTop = containerPadding + textViewVerticalInset

    /// Padding the placeholder must use so it lands exactly on the caret.
    static let placeholderLeadingPadding = textOriginLeading
    static let placeholderTopPadding = textOriginTop
}

/// Inline multiline text editor (for descriptions)
/// Supports markdown rendering when not editing, and @/#/! autocomplete while editing
struct InlineTextAreaEditor: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var onSave: (() -> Void)?

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var defaultTextColor: Color {
        colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary
    }
    private var mutedColor: Color {
        colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted
    }
    private var bgColor: Color {
        colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            Text(label)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

            if isEditing {
                // Standard TextEditor — no overlay, no cursor alignment issues
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        // Offset onto the TextEditor's real text origin so the
                        // placeholder and caret line up. A plain
                        // `.padding(containerPadding)` ignores the backing
                        // UITextView's internal insets — see InlineTextAreaMetrics.
                        Text(placeholder)
                            .font(Theme.Typography.body())
                            .foregroundColor(mutedColor)
                            .padding(.leading, InlineTextAreaMetrics.placeholderLeadingPadding)
                            .padding(.trailing, InlineTextAreaMetrics.placeholderLeadingPadding)
                            .padding(.top, InlineTextAreaMetrics.placeholderTopPadding)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(Theme.Typography.body())
                        .foregroundColor(defaultTextColor)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                        .padding(InlineTextAreaMetrics.containerPadding)
                        .focused($isFocused)
                        .onChange(of: isFocused) { _, focused in
                            if !focused && isEditing {
                                isEditing = false
                                onSave?()
                            }
                        }
                }
                .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isFocused = false
                        }
                    }
                }
            } else {
                // Display mode — render markdown and colored @mentions/#lists/!tasks
                Group {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Theme.Typography.body())
                            .foregroundColor(mutedColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.spacing12)
                            .background(bgColor)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    } else {
                        Text(text.attributedWithReferences(defaultColor: defaultTextColor))
                            .font(Theme.Typography.body())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.spacing12)
                            .background(bgColor)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                }
                .onTapGesture {
                    isEditing = true
                    isFocused = true
                }
            }
        }
    }
}
