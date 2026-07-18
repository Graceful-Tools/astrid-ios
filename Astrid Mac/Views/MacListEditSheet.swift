//  MacListEditSheet.swift
//  Astrid for Mac — create / edit a list (D1). Writes via ListService (offline-first).
//  Beyond name: description + color (Task 460f2bf7). Archive/icon-image are not backed by the
//  current service (no isArchived field; imageUrl needs an upload flow) — tracked separately.

#if os(macOS)
import SwiftUI

struct MacListEditSheet: View {
    let existing: TaskList?          // nil = create
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var listDescription = ""
    @State private var color = MacListEditSheet.palette[0]

    /// The shared list-color palette (hex), matching web/iOS.
    static let palette = ["#3b82f6", "#ef4444", "#f59e0b", "#10b981", "#8b5cf6",
                          "#ec4899", "#14b8a6", "#6366f1", "#64748b"]

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "New List" : "Edit List")
                .font(.headline).foregroundStyle(Theme.textPrimary)

            TextField("List name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if isValid { save() } }

            TextField("Description (optional)", text: $listDescription, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Color").font(.caption).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(Self.palette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Theme.textPrimary,
                                                           lineWidth: hex == color ? 2 : 0))
                            .onTapGesture { color = hex }
                            .accessibilityLabel(Text("Color \(hex)"))
                    }
                }
            }

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
        .frame(width: 340)
        .onAppear {
            name = existing?.name ?? ""
            listDescription = existing?.description ?? ""
            color = existing?.color ?? Self.palette[0]
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let desc = listDescription.trimmingCharacters(in: .whitespaces)
        let chosenColor = color
        MacActions.perform(existing == nil ? "Create list" : "Save list") {
            if let e = existing {
                _ = try await ListService.shared.updateListAdvanced(
                    listId: e.id, updates: ["name": n, "description": desc, "color": chosenColor])
            } else {
                _ = try await ListService.shared.createList(
                    name: n, description: desc.isEmpty ? nil : desc, color: chosenColor)
            }
            _ = try? await ListService.shared.fetchLists()
        }
        dismiss()
    }
}
#endif
