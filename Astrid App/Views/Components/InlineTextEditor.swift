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

    // Autocomplete state
    @State private var activeTrigger: AutocompleteItem.AutocompleteType?
    @State private var triggerPosition: String.Index?
    @State private var autocompleteItems: [AutocompleteItem] = []
    @State private var insertedReferences: [InsertedReference] = []
    @State private var filterTask: _Concurrency.Task<Void, Never>?

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
                // Autocomplete popup
                if activeTrigger != nil && !autocompleteItems.isEmpty {
                    AutocompletePopupView(
                        items: autocompleteItems,
                        activeTrigger: activeTrigger,
                        textColor: defaultTextColor,
                        mutedColor: mutedColor,
                        backgroundColor: bgColor,
                        borderColor: colorScheme == .dark ? Theme.Dark.inputBorder : Theme.inputBorder,
                        onSelect: { item in insertAutocompleteItem(item) },
                        onDismiss: { clearAutocomplete() }
                    )
                }

                // Text editor with colored overlay
                ZStack(alignment: .topLeading) {
                    // Colored overlay
                    Text(coloredAttributedString(text: text, references: insertedReferences, defaultColor: defaultTextColor))
                        .font(Theme.Typography.body())
                        .padding(Theme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)

                    // Invisible TextEditor
                    TextEditor(text: $text)
                        .font(Theme.Typography.body())
                        .foregroundColor(.clear)
                        .tint(defaultTextColor)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                        .padding(Theme.spacing12)
                        .focused($isFocused)
                        .onChange(of: text) { _, newValue in
                            handleTextChange(newValue)
                        }
                        .onChange(of: isFocused) { _, focused in
                            if !focused && isEditing {
                                isEditing = false
                                // Reconstruct references before saving
                                text = reconstructReferencesInText(text, references: insertedReferences)
                                insertedReferences = []
                                clearAutocomplete()
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
                // Render with colored references when not editing
                if text.isEmpty {
                    Text(placeholder)
                        .font(Theme.Typography.body())
                        .foregroundColor(mutedColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing12)
                        .background(bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .onTapGesture {
                            isEditing = true
                            isFocused = true
                        }
                } else {
                    Text(text.attributedWithReferences(defaultColor: defaultTextColor))
                        .font(Theme.Typography.body())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing12)
                        .background(bgColor)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .onTapGesture {
                            isEditing = true
                            isFocused = true
                        }
                }
            }
        }
    }

    // MARK: - Autocomplete

    private func handleTextChange(_ newValue: String) {
        insertedReferences.removeAll { ref in !newValue.contains(ref.displayText) }

        if let trigger = detectAutocompleteTrigger(in: newValue) {
            activeTrigger = trigger.type
            triggerPosition = trigger.position
            filterItems(type: trigger.type, search: trigger.search)
        } else {
            clearAutocomplete()
        }
    }

    private func filterItems(type: AutocompleteItem.AutocompleteType, search: String) {
        filterTask?.cancel()
        filterTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 80_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            let results: [AutocompleteItem]
            switch type {
            case .mention: results = filterMentionItems(users: buildMentionableUsers(), search: search)
            case .list: results = filterListItems(search: search)
            case .task: results = filterTaskItems(search: search)
            }
            await MainActor.run {
                guard !_Concurrency.Task.isCancelled else { return }
                autocompleteItems = results
            }
        }
    }

    private func insertAutocompleteItem(_ item: AutocompleteItem) {
        guard let pos = triggerPosition else { return }
        let displayText = "\(item.triggerChar)\(item.label)"
        let textBefore = String(text[text.startIndex..<pos])
        text = textBefore + displayText + " "
        insertedReferences.append(InsertedReference(id: item.id, type: item.type, displayText: displayText))
        clearAutocomplete()
    }

    private func clearAutocomplete() {
        activeTrigger = nil
        triggerPosition = nil
        autocompleteItems = []
        filterTask?.cancel()
    }
}
