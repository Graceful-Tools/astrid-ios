//  MacListEditSheet.swift
//  Astrid for Mac — create / edit a list (D1). Writes via ListService (offline-first).
//  Beyond name: description + color (Task 460f2bf7). Archive/icon-image are not backed by the
//  current service (no isArchived field; imageUrl needs an upload flow) — tracked separately.

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacListEditSheet: View {
    let existing: TaskList?          // nil = create
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var listDescription = ""
    @State private var color = MacListEditSheet.palette[0]
    @State private var imageUrl: String?
    @State private var uploadingImage = false
    @State private var defPriority = 0
    @State private var defDueDate = "none"
    @State private var defRepeating = "never"

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
                .accessibilityIdentifier("listEdit.name")
                .onSubmit { if isValid { save() } }

            TextField("Description (optional)", text: $listDescription, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)

            // Image upload — only for an existing list (upload needs the list id). Task 383b96af.
            if let e = existing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Image").font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        imagePreview
                        Button(uploadingImage ? "Uploading…" : "Choose Image…") { pickImage(for: e) }
                            .disabled(uploadingImage)
                        if imageUrl != nil {
                            Button("Remove") { setImage(nil, for: e) }.foregroundStyle(Theme.error)
                        }
                    }
                }
            }

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

            // Default task settings — applied to new tasks in this list (edit mode). Task c82173ff.
            if existing != nil {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("New-task defaults").font(.caption).foregroundStyle(Theme.textSecondary)
                    Picker("Priority", selection: $defPriority) {
                        ForEach(MacTaskVisuals.allPriorities, id: \.self) { p in
                            Text(MacTaskVisuals.priorityLabel(p)).tag(p.rawValue)
                        }
                    }.onChange(of: defPriority) { saveDefaults() }
                    Picker("Due date", selection: $defDueDate) {
                        ForEach(MacListDefaults.dueDate) { Text($0.label).tag($0.value) }
                    }.onChange(of: defDueDate) { saveDefaults() }
                    Picker("Repeat", selection: $defRepeating) {
                        ForEach(MacListDefaults.repeating) { Text($0.label).tag($0.value) }
                    }.onChange(of: defRepeating) { saveDefaults() }
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
        .background(Theme.bgPrimary)
        .onAppear {
            name = existing?.name ?? ""
            listDescription = existing?.description ?? ""
            color = existing?.color ?? Self.palette[0]
            imageUrl = existing?.imageUrl
            defPriority = existing?.defaultPriority ?? 0
            defDueDate = existing?.defaultDueDate ?? "none"
            defRepeating = existing?.defaultRepeating ?? "never"
        }
    }

    private func saveDefaults() {
        guard let e = existing else { return }
        let updates = MacListDefaults.updates(priority: defPriority, dueDate: defDueDate, repeating: defRepeating)
        MacActions.perform("Update list defaults") {
            _ = try await ListService.shared.updateListAdvanced(listId: e.id, updates: updates)
        }
    }

    private var fullImageURL: URL? {
        guard let s = imageUrl, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: Constants.API.baseURL + s)
    }

    @ViewBuilder private var imagePreview: some View {
        if let url = fullImageURL {
            CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                placeholder: { Color(hex: color) ?? .gray }
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color(hex: color) ?? .gray).frame(width: 36, height: 36)
        }
    }

    private func pickImage(for list: TaskList) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = MacListImage.contentTypes
        guard panel.runModal() == .OK, let url = panel.url, MacListImage.isSupported(filename: url.lastPathComponent) else { return }
        let name = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        uploadingImage = true
        _Concurrency.Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { await MainActor.run { uploadingImage = false }; return }
            do {
                let uploadedUrl = try await AttachmentService.shared.uploadToSecureEndpoint(
                    fileData: data, fileName: name, mimeType: mime, context: ["listId": list.id])
                await MainActor.run { uploadingImage = false; setImage(uploadedUrl, for: list) }
            } catch {
                await MainActor.run { uploadingImage = false }
            }
        }
    }

    private func setImage(_ url: String?, for list: TaskList) {
        imageUrl = url
        MacActions.perform("Update list image") {
            _ = try await ListService.shared.updateListAdvanced(listId: list.id, updates: ["imageUrl": url ?? ""])
            _ = try? await ListService.shared.fetchLists()
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
