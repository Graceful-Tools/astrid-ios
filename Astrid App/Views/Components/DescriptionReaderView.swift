//  DescriptionReaderView.swift
//  Astrid for iOS — the description, full screen. (Task AITD-577)
//
//  The detail sheet draws a description in a few-line box with its markdown flattened, which is
//  fine for "buy milk" and unreadable for an agent's plan. This is the room for the long ones:
//  block markdown, the whole screen, and — on a task you can edit — a full-height editor.
//  When it is offered and what it saves are `DescriptionReader`'s, pinned in its tests.

import SwiftUI

/// The expand button beside the Description label, and the reader it opens.
struct DescriptionExpandButton: View {
    @ThemedPalette private var palette
    @Binding var text: String
    var isReadOnly: Bool = false
    var onSave: (() -> Void)?

    @State private var isPresented = false

    var body: some View {
        if DescriptionReader.offersFullScreen(text: text, isReadOnly: isReadOnly) {
            Button {
                isPresented = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("task_detail.description.full_screen", comment: "Open the description full screen"))
            .accessibilityIdentifier("taskDetail.description.expand")
            .fullScreenCover(isPresented: $isPresented) {
                DescriptionReaderView(text: $text, isReadOnly: isReadOnly, onSave: onSave)
            }
        }
    }
}

/// A task you can only read: its description, and the way into the reader.
struct ReadOnlyDescriptionRow: View {
    @ThemedPalette private var palette
    @Binding var text: String

    var body: some View {
        TwoColumnRow(label: "Description") {
            HStack(alignment: .top, spacing: 0) {
                Text(text)
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DescriptionExpandButton(text: $text, isReadOnly: true)
            }
        }
    }
}

struct DescriptionReaderView: View {
    @ThemedPalette private var palette
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    let isReadOnly: Bool
    var onSave: (() -> Void)?

    @State private var draft: String
    @State private var mode: DescriptionReader.Mode
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, isReadOnly: Bool, onSave: (() -> Void)?) {
        _text = text
        self.isReadOnly = isReadOnly
        self.onSave = onSave
        _draft = State(initialValue: text.wrappedValue)
        _mode = State(initialValue: DescriptionReader.initialMode(text: text.wrappedValue, isReadOnly: isReadOnly))
    }

    private var textColor: Color { palette.textPrimary }
    private var background: Color { palette.bgPrimary }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .reading:
                    ScrollView {
                        MarkdownText(source: draft, defaultColor: textColor)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.spacing16)
                    }
                    .accessibilityIdentifier("descriptionReader.reading")
                case .editing:
                    TextEditor(text: $draft)
                        .font(Theme.Typography.body())
                        .foregroundColor(textColor)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Theme.spacing12)
                        .focused($isFocused)
                        .accessibilityIdentifier("descriptionReader.editor")
                        .onAppear { isFocused = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .navigationTitle(NSLocalizedString("tasks.description", comment: "Description"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isReadOnly {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(mode == .reading
                               ? NSLocalizedString("actions.edit", comment: "Edit")
                               : NSLocalizedString("task_detail.description.preview", comment: "Show the description as it reads")) {
                            mode = (mode == .reading) ? .editing : .reading
                        }
                        .accessibilityIdentifier("descriptionReader.toggleMode")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("actions.done", comment: "Done")) { close() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("descriptionReader.done")
                }
            }
        }
    }

    private func close() {
        if !isReadOnly, let saved = DescriptionReader.textToSave(edited: draft, original: text) {
            text = saved
            onSave?()
        }
        dismiss()
    }
}
