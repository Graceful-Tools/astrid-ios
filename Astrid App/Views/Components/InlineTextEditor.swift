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
                        Text(placeholder)
                            .font(Theme.Typography.body())
                            .foregroundColor(mutedColor)
                            .padding(Theme.spacing12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(Theme.Typography.body())
                        .foregroundColor(defaultTextColor)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                        .padding(Theme.spacing12)
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
