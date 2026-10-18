//  MacTaskProjectFieldsRows.swift
//  Astrid for Mac — a GitHub board's project fields in a task's editor (AITD-491; the Mac half of
//  iOS `TaskDetailProjectFieldsRows`, web `TaskProjectFieldsSection.tsx`).
//
//  Which fields, their order and an iteration's choices are astrid-core's; reading and saving go
//  through `ProjectFieldService`, shared with iOS. A task off a GitHub board gets no rows.

#if os(macOS)
import SwiftUI

struct MacTaskProjectFieldsRows: View {
    let task: Task

    @State private var fields = TaskProjectFields.none
    @State private var saving: String?
    @State private var error: (rowId: String, key: String)?

    private let service = ProjectFieldService.shared

    var body: some View {
        Group {
            ForEach(fields.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: MacDetailRowMetrics.columnGap) {
                    Text(Image(systemName: Self.icon(for: row.kind)))
                        .macFont(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: MacDetailRowMetrics.leadingColumnWidth)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.name)
                                .foregroundStyle(Theme.textMuted)
                            MacProjectFieldEditor(row: row, isDisabled: saving == row.id,
                                                  onSave: { save(row, $0) })
                        }
                        if let error, error.rowId == row.id {
                            Text(NSLocalizedString(error.key, comment: ""))
                                .macFont(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .task(id: task.id) {
            if let loaded = try? await service.fields(taskId: task.id) { fields = loaded }
        }
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

private struct MacProjectFieldEditor: View {
    let row: ProjectFieldRow
    let isDisabled: Bool
    let onSave: (ProjectFieldValue?) -> Void

    @State private var draft = ""

    private var empty: String { NSLocalizedString("tasks.projectFields.empty", comment: "") }

    var body: some View {
        switch row.kind {
        case .singleSelect, .iteration:
            Menu(row.displayText() ?? empty) {
                Button(NSLocalizedString("tasks.projectFields.clear", comment: "")) { onSave(nil) }
                Divider()
                if row.kind == .singleSelect {
                    ForEach(row.options) { option in Button(option.name) { onSave(.text(option.id)) } }
                } else {
                    ForEach(row.iterations) { iteration in Button(iteration.title) { onSave(.text(iteration.id)) } }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isDisabled)
        case .date:
            if let text = row.value?.text, let day = ProjectFieldRow.day(from: text) {
                HStack(spacing: 6) {
                    DatePicker("", selection: Binding(
                        get: { ProjectFieldRow.localDay(day) },
                        set: { onSave(.text(ProjectFieldRow.dayText(from: $0))) }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                    Button { onSave(nil) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(NSLocalizedString("tasks.projectFields.clear", comment: ""))
                }
                .disabled(isDisabled)
            } else {
                Button(empty) { onSave(.text(ProjectFieldRow.dayText(from: Date()))) }
                    .buttonStyle(.borderless)
                    .disabled(isDisabled)
            }
        case .text, .number, .none:
            TextField(empty, text: $draft)
                .textFieldStyle(.plain)
                .onSubmit(commit)
                .onAppear { draft = row.editableText }
                .onChange(of: row.value) { _, _ in draft = row.editableText }
                .onDisappear(perform: commit)
                .disabled(isDisabled)
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != row.editableText else { return }
        if trimmed.isEmpty { onSave(nil); return }
        if row.kind == .number {
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
#endif
