//  TaskDetailProjectFieldsRows.swift
//  A GitHub board's project fields in task details (AITD-491; web AWTD-1210,
//  `TaskProjectFieldsSection.tsx`).
//
//  Fields are defined in GitHub and every unmapped one shows here, one row each. Which fields,
//  their order and an iteration's choices are astrid-core's; reading and saving go through
//  `ProjectFieldService`. A task off a GitHub board gets no rows, so its details are unchanged.

import SwiftUI

struct TaskDetailProjectFieldsRows: View {
    let task: Task
    let isReadOnly: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var fields = TaskProjectFields.none
    @State private var saving: String?
    @State private var error: (rowId: String, key: String)?

    private let service = ProjectFieldService.shared

    var body: some View {
        Group {
            ForEach(fields.rows) { row in
                TwoColumnRow(label: row.name, icon: Self.icon(for: row.kind)) {
                    VStack(alignment: .leading, spacing: Theme.spacing4) {
                        ProjectFieldEditor(row: row,
                                           isDisabled: isReadOnly || saving == row.id,
                                           onSave: { save(row, $0) })
                        if let error, error.rowId == row.id {
                            Text(NSLocalizedString(error.key, comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .task(id: task.id) { await load() }
    }

    static func icon(for kind: ProjectFieldRow.Kind?) -> String {
        switch kind {
        case .number: return "number"
        case .date: return "calendar"
        case .singleSelect: return "list.bullet.circle"
        case .iteration: return "arrow.triangle.2.circlepath"
        case .text, .none: return "text.alignleft"
        }
    }

    private func load() async {
        if let loaded = try? await service.fields(taskId: task.id) { fields = loaded }
    }

    private func save(_ row: ProjectFieldRow, _ value: ProjectFieldValue?) {
        guard value != row.value else { return }
        saving = row.id
        error = nil
        _Concurrency.Task {
            do {
                fields = try await service.set(taskId: task.id, fieldId: row.id, value: value)
            } catch {
                self.error = (row.id, ProjectFieldErrors.messageKey(for: error))
            }
            saving = nil
        }
    }
}

/// One field's editor, by type: a menu for a single-select or an iteration, a date picker, or a
/// text field committed on Return. Read-only, the value as words.
struct ProjectFieldEditor: View {
    let row: ProjectFieldRow
    let isDisabled: Bool
    let onSave: (ProjectFieldValue?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = ""

    private var empty: String { NSLocalizedString("tasks.projectFields.empty", comment: "") }
    private var textPrimary: Color { colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary }
    private var textMuted: Color { colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted }

    var body: some View {
        switch row.kind {
        case .singleSelect, .iteration:
            Menu {
                Button(NSLocalizedString("tasks.projectFields.clear", comment: "")) { onSave(nil) }
                if row.kind == .singleSelect {
                    ForEach(row.options) { option in
                        Button(option.name) { onSave(.text(option.id)) }
                    }
                } else {
                    ForEach(row.iterations) { iteration in
                        Button(iteration.title) { onSave(.text(iteration.id)) }
                    }
                }
            } label: {
                valueChip
            }
            .disabled(isDisabled)
        case .date:
            HStack(spacing: Theme.spacing8) {
                if let text = row.value?.text, let day = ProjectFieldRow.day(from: text) {
                    DatePicker("", selection: Binding(
                        get: { ProjectFieldRow.localDay(day) },
                        set: { onSave(.text(ProjectFieldRow.dayText(from: $0))) }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .disabled(isDisabled)
                    if !isDisabled {
                        Button { onSave(nil) } label: { Image(systemName: "xmark.circle.fill").foregroundColor(textMuted) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(NSLocalizedString("tasks.projectFields.clear", comment: ""))
                    }
                } else {
                    Button { onSave(.text(ProjectFieldRow.dayText(from: Date()))) } label: { valueChip }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                }
            }
        case .text, .number, .none:
            if isDisabled {
                valueChip
            } else {
                TextField(empty, text: $draft)
                    .font(Theme.Typography.body())
                    .keyboardType(row.kind == .number ? .decimalPad : .default)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .onAppear { draft = row.editableText }
                    .onChange(of: row.value) { _, _ in draft = row.editableText }
                    .onDisappear(perform: commit)
            }
        }
    }

    private var valueChip: some View {
        Text(row.displayText() ?? empty)
            .font(Theme.Typography.body())
            .foregroundColor(row.value == nil ? textMuted : textPrimary)
            .lineLimit(1)
            .chipBackground(colorScheme)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != row.editableText else { return }
        if trimmed.isEmpty { onSave(nil); return }
        if row.kind == .number {
            // Typed in the reader's own format ("2,5" in German), sent as a number.
            guard let number = (try? Double(trimmed, format: .number)) ?? Double(trimmed) else {
                draft = row.editableText
                return
            }
            onSave(.number(number))
        } else {
            onSave(.text(trimmed))
        }
    }
}
