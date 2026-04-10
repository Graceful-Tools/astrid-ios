import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "RichTextInput")

/// Reusable rich text input with @mention, #list, !task autocomplete, colored references,
/// file attachments, and send button. Used by both chat messages and task comments.
struct RichTextInput: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    // Configuration
    var placeholder: String = "Message..."
    var listId: String? = nil              // For upload context and mention scoping
    var availableAgents: [User] = []       // AI agents for @mention
    var uploadContext: [String: String] = [:]  // For attachment uploads

    // Callbacks
    var onSend: ((_ content: String, _ type: Comment.CommentType, _ fileId: String?) -> Void)?

    // Text state (can be bound externally or managed internally)
    @State private var text = ""
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    // Autocomplete state
    @State private var activeTrigger: AutocompleteItem.AutocompleteType?
    @State private var triggerPosition: String.Index?
    @State private var autocompleteItems: [AutocompleteItem] = []
    @State private var selectedIndex: Int = 0
    @State private var insertedReferences: [InsertedReference] = []

    // Attachment state
    @StateObject private var attachmentService = AttachmentService.shared
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var attachedFile: AttachedFileInfo?
    @State private var isUploadingFile = false
    @State private var uploadError: String?

    private var effectiveTheme: ThemeMode {
        themeMode == .auto ? (colorScheme == .dark ? .dark : .light) : themeMode
    }
    private var isOceanTheme: Bool { effectiveTheme == .ocean }
    private var showAutocomplete: Bool { activeTrigger != nil && !autocompleteItems.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Autocomplete popup
            if showAutocomplete {
                autocompletePopup
            }

            // Attachment preview
            if let file = attachedFile {
                attachmentPreview(file: file)
            }

            // Upload error
            if let error = uploadError {
                Text(error)
                    .font(Theme.Typography.caption2())
                    .foregroundColor(Theme.error)
                    .padding(.horizontal, Theme.spacing12)
                    .padding(.bottom, Theme.spacing4)
            }

            // Main input row: [text field] [paperclip] [send]
            HStack(alignment: .bottom, spacing: Theme.spacing8) {
                // Text input with colored references
                ZStack(alignment: .topLeading) {
                    // Colored overlay
                    Text(coloredDisplayText)
                        .font(Theme.Typography.body())
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)

                    // Placeholder
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Theme.Typography.body())
                            .foregroundColor(placeholderColor)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    // Invisible TextEditor
                    TextEditor(text: $text)
                        .font(Theme.Typography.body())
                        .foregroundColor(.clear)
                        .tint(textColor)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .onChange(of: text) { _, newValue in
                            handleTextChange(newValue)
                        }
                        .onKeyPress(.upArrow) {
                            guard showAutocomplete else { return .ignored }
                            selectedIndex = selectedIndex <= 0 ? autocompleteItems.count - 1 : selectedIndex - 1
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            guard showAutocomplete else { return .ignored }
                            selectedIndex = selectedIndex >= autocompleteItems.count - 1 ? 0 : selectedIndex + 1
                            return .handled
                        }
                        .onKeyPress(.tab) {
                            guard showAutocomplete, autocompleteItems.indices.contains(selectedIndex) else { return .ignored }
                            insertItem(autocompleteItems[selectedIndex])
                            return .handled
                        }
                        .onKeyPress(.return) {
                            if showAutocomplete, autocompleteItems.indices.contains(selectedIndex) {
                                insertItem(autocompleteItems[selectedIndex])
                                return .handled
                            }
                            return .ignored
                        }
                        .onKeyPress(.escape) {
                            guard showAutocomplete else { return .ignored }
                            clearAutocomplete()
                            return .handled
                        }
                }
                .frame(minHeight: 36, maxHeight: 200)
                .fixedSize(horizontal: false, vertical: true)
                .background(inputBackgroundColor)
                .cornerRadius(Theme.radiusMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(inputBorderColor, lineWidth: 1)
                )

                // Paperclip
                Menu {
                    Button { showingPhotoPicker = true } label: {
                        Label(NSLocalizedString("attachments.choose_photo", comment: "Choose Photo"), systemImage: "photo")
                    }
                    Button { showingDocumentPicker = true } label: {
                        Label(NSLocalizedString("attachments.choose_document", comment: "Choose Document"), systemImage: "doc")
                    }
                } label: {
                    Image(systemName: isUploadingFile ? "arrow.up.circle" : "paperclip")
                        .font(.system(size: 16))
                        .foregroundColor(isUploadingFile ? .gray : Theme.accent)
                        .padding(10)
                        .background(isOceanTheme ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
                .disabled(isUploadingFile || isSubmitting)

                // Send
                Button { send() } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundColor(canSend ? Theme.accent : mutedTextColor)
                        .padding(10)
                        .background(isOceanTheme ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSubmitting)
            }
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background(containerBackground)
        .cornerRadius(Theme.radiusLarge)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 0)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            if let item = item {
                _Concurrency.Task { await handlePhotoSelection(item) }
            }
        }
        .fileImporter(isPresented: $showingDocumentPicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                _Concurrency.Task { await handleDocumentSelection(url) }
            }
        }
    }

    // MARK: - Computed

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedFile != nil
    }

    // MARK: - Send

    private func send() {
        let refs = insertedReferences
        var content = text
        let sorted = refs.sorted { $0.displayText.count > $1.displayText.count }
        for ref in sorted {
            let fullRef = "\(ref.displayText.prefix(1))[\(ref.displayText.dropFirst())](\(ref.id))"
            if let range = content.range(of: ref.displayText) {
                content = content.replacingCharacters(in: range, with: fullRef)
            }
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty || attachedFile != nil else { return }
        guard !isSubmitting else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        let fileId = attachedFile?.fileId
        let messageType: Comment.CommentType = attachedFile != nil ? .ATTACHMENT : .TEXT

        text = ""
        insertedReferences = []
        attachedFile = nil
        uploadError = nil
        clearAutocomplete()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSend?(content, messageType, fileId)
    }

    // MARK: - Autocomplete

    private func handleTextChange(_ newValue: String) {
        insertedReferences.removeAll { ref in !newValue.contains(ref.displayText) }
        if let trigger = detectAutocompleteTrigger(in: newValue) {
            activeTrigger = trigger.type
            triggerPosition = trigger.position
            selectedIndex = 0
            let results: [AutocompleteItem]
            switch trigger.type {
            case .mention:
                var users = buildMentionableUsers(listId: listId)
                for agent in availableAgents where !users.contains(where: { $0.id == agent.id }) {
                    users.append(agent)
                }
                results = filterMentionItems(users: users, search: trigger.search)
            case .list:
                results = filterListItems(search: trigger.search)
            case .task:
                results = filterTaskItems(search: trigger.search, selectedListId: listId)
            }
            autocompleteItems = results
        } else {
            clearAutocomplete()
        }
    }

    private func insertItem(_ item: AutocompleteItem) {
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
        selectedIndex = 0
    }

    // MARK: - Colored Display Text

    private var coloredDisplayText: AttributedString {
        coloredAttributedString(text: text, references: insertedReferences, defaultColor: textColor)
    }

    // MARK: - Autocomplete Popup

    private var autocompletePopup: some View {
        AutocompletePopupView(
            items: autocompleteItems,
            activeTrigger: activeTrigger,
            textColor: textColor,
            mutedColor: mutedTextColor,
            backgroundColor: containerBackgroundColor,
            borderColor: inputBorderColor,
            onSelect: { item in insertItem(item) },
            onDismiss: { clearAutocomplete() }
        )
    }

    // MARK: - Attachment Preview

    @ViewBuilder
    private func attachmentPreview(file: AttachedFileInfo) -> some View {
        HStack(spacing: Theme.spacing8) {
            if file.isImage, let imageData = file.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(inputBackgroundColor)
                        .frame(width: 56, height: 56)
                    Image(systemName: "doc")
                        .font(.system(size: 20))
                        .foregroundColor(mutedTextColor)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName).font(Theme.Typography.caption1()).foregroundColor(textColor).lineLimit(1)
                Text(formatFileSize(file.fileSize)).font(Theme.Typography.caption2()).foregroundColor(mutedTextColor)
            }
            Spacer()
            Button {
                if file.fileId.hasPrefix("temp_") { attachmentService.cancelUpload(tempFileId: file.fileId) }
                attachedFile = nil
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(mutedTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spacing12)
        .padding(.bottom, Theme.spacing4)
    }

    // MARK: - File Handling

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        isUploadingFile = true
        uploadError = nil
        defer { isUploadingFile = false; selectedPhotoItem = nil }

        var photoData: Data?
        photoData = try? await item.loadTransferable(type: Data.self)
        if photoData == nil {
            struct ImageTransfer: Transferable {
                let data: Data
                static var transferRepresentation: some TransferRepresentation {
                    DataRepresentation(importedContentType: .image) { data in ImageTransfer(data: data) }
                }
            }
            if let transfer = try? await item.loadTransferable(type: ImageTransfer.self) {
                photoData = UIImage(data: transfer.data)?.jpegData(compressionQuality: 0.85)
            }
        }

        guard let data = photoData, data.count <= 100 * 1024 * 1024 else {
            uploadError = photoData == nil ? "Failed to load photo" : "File size cannot exceed 100MB"
            return
        }

        let fileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        let tempFileId = attachmentService.saveLocallyAndUploadAsync(fileData: data, fileName: fileName, mimeType: "image/jpeg", context: uploadContext)
        attachedFile = AttachedFileInfo(fileId: tempFileId, fileName: fileName, fileSize: data.count, mimeType: "image/jpeg", imageData: data)
    }

    private func handleDocumentSelection(_ url: URL) async {
        isUploadingFile = true
        uploadError = nil
        defer { isUploadingFile = false }
        guard url.startAccessingSecurityScopedResource() else { uploadError = "Cannot access file"; return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url), data.count <= 100 * 1024 * 1024 else {
            uploadError = "Failed to read file or file too large"
            return
        }
        let fileName = url.lastPathComponent
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let tempFileId = attachmentService.saveLocallyAndUploadAsync(fileData: data, fileName: fileName, mimeType: mimeType, context: uploadContext)
        attachedFile = AttachedFileInfo(fileId: tempFileId, fileName: fileName, fileSize: data.count, mimeType: mimeType, imageData: mimeType.hasPrefix("image/") ? data : nil)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    // MARK: - Theme

    private var textColor: Color { isOceanTheme ? Theme.Ocean.textPrimary : effectiveTheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary }
    private var mutedTextColor: Color { isOceanTheme ? Theme.Ocean.textMuted : effectiveTheme == .dark ? Theme.Dark.textMuted : Theme.textMuted }
    private var placeholderColor: Color { isOceanTheme ? Color(UIColor.darkGray) : effectiveTheme == .dark ? Theme.Dark.textMuted : Theme.textMuted }
    private var inputBackgroundColor: Color { effectiveTheme == .dark ? Theme.Dark.inputBg : Color.white }
    private var inputBorderColor: Color { effectiveTheme == .dark ? Theme.Dark.inputBorder : Theme.Ocean.inputBorder }
    @ViewBuilder var containerBackground: some View {
        if effectiveTheme == .light { Rectangle().fill(Theme.LiquidGlass.secondaryGlassMaterial) } else { containerBackgroundColor }
    }
    private var containerBackgroundColor: Color { effectiveTheme == .dark ? Theme.Dark.bgPrimary : Color.white.opacity(0.8) }
}
