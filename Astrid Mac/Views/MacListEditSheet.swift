//  MacListEditSheet.swift
//  Astrid for Mac — create / rename a list (D1). Writes via ListService (offline-first).

#if os(macOS)
import SwiftUI

struct MacListEditSheet: View {
    let existing: TaskList?          // nil = create
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "New List" : "Rename List")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            TextField("List name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if isValid { save() } }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button(existing == nil ? "Create" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { name = existing?.name ?? "" }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        _Concurrency.Task {
            if let e = existing {
                _ = try? await ListService.shared.updateList(listId: e.id, name: n)
            } else {
                _ = try? await ListService.shared.createList(name: n)
            }
            _ = try? await ListService.shared.fetchLists()
        }
        dismiss()
    }
}
#endif
