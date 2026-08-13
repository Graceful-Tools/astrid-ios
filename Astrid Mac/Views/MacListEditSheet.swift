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
    @State private var defDueTime: String?
    /// Recently-completed window, via the SHARED presets iOS and web read (task 545812e6).
    @State private var recentlyCompleted: RecentlyCompletedPresetId = .default24h
    @State private var recentlyCompletedDate = Date()

    /// The shared list-color palette (hex), matching web/iOS.
    static let palette = ["#3b82f6", "#ef4444", "#f59e0b", "#10b981", "#8b5cf6",
                          "#ec4899", "#14b8a6", "#6366f1", "#64748b"]

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "New List" : "Edit List")
                .font(.headline).foregroundStyle(Theme.textPrimary)

            TextField(NSLocalizedString("lists.list_name", comment: ""), text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("listEdit.name")
                .onSubmit { if isValid { save() } }

            TextField(NSLocalizedString("tasks.description", comment: ""), text: $listDescription, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)

            // Image upload — only for an existing list (upload needs the list id). Task 383b96af.
            if let e = existing {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("mac.image", comment: "")).font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        imagePreview
                        Button(uploadingImage ? "Uploading…" : "Choose Image…") { pickImage(for: e) }
                            .disabled(uploadingImage)
                        if imageUrl != nil {
                            Button(NSLocalizedString("actions.remove", comment: "")) { setImage(nil, for: e) }.foregroundStyle(Theme.error)
                        }
                    }
                }
            }

            // A LIST IMAGE, not a colour picker (task 9a9d24bd). Same 16 placeholders iOS and
            // web offer, read from the shared palette so the platforms cannot drift apart.
            // Unlike an upload these are just paths, so one can be chosen while CREATING a list,
            // which the upload button below cannot do (it needs a list id to post to).
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("mac.image", comment: "")).font(.caption).foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
                          spacing: 6) {
                    ForEach(ListImagePlaceholders.all) { placeholder in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(hex: placeholder.colorHex) ?? .gray)
                            .frame(height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Theme.accent,
                                              lineWidth: imageUrl == placeholder.path ? 2 : 0))
                            .contentShape(RoundedRectangle(cornerRadius: 5))
                            .onTapGesture { choosePlaceholder(placeholder) }
                            .help(placeholder.name)
                            .accessibilityLabel(Text(placeholder.name))
                    }
                }
            }

            // Default task settings — applied to new tasks in this list (edit mode). Task c82173ff.
            if existing != nil {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("mac.new_task_defaults", comment: "")).font(.caption).foregroundStyle(Theme.textSecondary)
                    Picker(NSLocalizedString("tasks.priority", comment: ""), selection: $defPriority) {
                        ForEach(MacTaskVisuals.allPriorities, id: \.self) { p in
                            Text(MacTaskVisuals.priorityLabel(p)).tag(p.rawValue)
                        }
                    }.onChange(of: defPriority) { saveDefaults() }
                    Picker(NSLocalizedString("lists.due_date", comment: ""), selection: $defDueDate) {
                        ForEach(MacListDefaults.dueDate) { Text($0.label).tag($0.value) }
                    }.onChange(of: defDueDate) { saveDefaults() }
                    Picker(NSLocalizedString("Repeat", comment: ""), selection: $defRepeating) {
                        ForEach(MacListDefaults.repeating) { Text($0.label).tag($0.value) }
                    }.onChange(of: defRepeating) { saveDefaults() }
                    // Was missing on Mac entirely (task 545812e6).
                    Picker(NSLocalizedString("tasks.due_time", comment: ""), selection: $defDueTime) {
                        ForEach(MacListDefaults.dueTime, id: \.value) { Text($0.label).tag($0.value) }
                    }.onChange(of: defDueTime) { saveDueTime() }
                }

                // Recently completed window — the shared presets, so Mac shows the same nine
                // options in the same order as iOS and web rather than its own list.
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Picker(NSLocalizedString("lists.recently_completed", comment: ""),
                           selection: $recentlyCompleted) {
                        ForEach(RECENTLY_COMPLETED_PRESETS, id: \.id) { Text($0.label).tag($0.id) }
                    }.onChange(of: recentlyCompleted) { saveRecentlyCompleted() }
                    if recentlyCompleted == .sinceSpecificDate {
                        DatePicker(NSLocalizedString("mac.since", comment: ""),
                                   selection: $recentlyCompletedDate, displayedComponents: [.date])
                            .onChange(of: recentlyCompletedDate) { saveRecentlyCompleted() }
                    }
                }
            }

            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
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
            defDueTime = existing?.defaultDueTime
            recentlyCompleted = findPresetForWindow(existing?.recentlyCompletedWindow)?.id ?? .default24h
            if case let .sinceDate(day) = existing?.recentlyCompletedWindow {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                recentlyCompletedDate = f.date(from: day) ?? Date()
            }
        }
    }

    /// Pick a placeholder. For an existing list this saves straight away, like the upload path;
    /// while CREATING one there is no id yet, so it rides along in the create payload.
    private func choosePlaceholder(_ placeholder: ListImagePlaceholders.Placeholder) {
        imageUrl = placeholder.path
        // The palette pairs each image with its own pastel, so the list's colour follows the
        // picture rather than staying whatever blue the old default happened to be.
        color = placeholder.colorHex
        guard let e = existing else { return }
        // BOTH, in one write. Sending only the image meant the colour changed on screen and then
        // reverted on the next fetch unless you also happened to press Save (task da56d096).
        MacActions.perform("Set list image") {
            _ = try await ListService.shared.updateListAdvanced(
                listId: e.id,
                updates: ["imageUrl": placeholder.path, "color": placeholder.colorHex])
        }
    }

    private func saveDueTime() {
        guard let e = existing else { return }
        MacActions.perform("Update default due time") {
            _ = try await ListService.shared.updateListAdvanced(
                listId: e.id, updates: ["defaultDueTime": defDueTime as Any? ?? NSNull()])
        }
    }

    private func saveRecentlyCompleted() {
        guard let e = existing else { return }
        let window: RecentlyCompletedWindow?
        if recentlyCompleted == .sinceSpecificDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            window = .sinceDate(date: f.string(from: recentlyCompletedDate))
        } else {
            window = presetForValue(recentlyCompleted)
        }
        MacActions.perform("Update recently completed window") {
            _ = try await ListService.shared.updateListAdvanced(
                listId: e.id, updates: ["recentlyCompletedWindow": window?.updatePayloadValue ?? NSNull()])
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
        let chosenImage = imageUrl
        MacActions.perform(existing == nil ? "Create list" : "Save list") {
            if let e = existing {
                _ = try await ListService.shared.updateListAdvanced(
                    listId: e.id, updates: ["name": n, "description": desc, "color": chosenColor])
            } else {
                let created = try await ListService.shared.createList(
                    name: n, description: desc.isEmpty ? nil : desc, color: chosenColor)
                // A placeholder chosen before the list existed has to be applied once it does —
                // there was no id to attach it to at the time.
                if let chosenImage {
                    _ = try await ListService.shared.updateListAdvanced(
                        listId: created.id, updates: ["imageUrl": chosenImage])
                }
            }
            _ = try? await ListService.shared.fetchLists()
        }
        dismiss()
    }
}
#endif
