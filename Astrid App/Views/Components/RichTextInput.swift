import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "RichTextInput")

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
    /// Several files can be staged at once, so this hands back a LIST. The host decides how
    /// to spend them — for comments that is one comment per file, via CommentAttachmentBatch.
    var onSend: ((_ content: String, _ type: Comment.CommentType, _ fileIds: [String]) -> Void)?
    var onTimerTap: (() -> Void)? = nil    // Task detail only: timer in the send slot while input is empty
    var focusReport: Binding<Bool>? = nil  // Reports the text field's focus to the host view

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
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var showingCamera = false
    @State private var attachedFiles: [AttachedFileInfo] = []
    @State private var isUploadingFile = false
    @State private var uploadError: String?

    private var effectiveTheme: ThemeMode {
        themeMode == .auto ? (colorScheme == .dark ? .dark : .light) : themeMode
    }
    private var isOceanTheme: Bool { effectiveTheme == .ocean }
    private var showAutocomplete: Bool { activeTrigger != nil && !autocompleteItems.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Attachment previews — a strip, since several files can be staged at once.
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacing8) {
                        ForEach(attachedFiles, id: \.fileId) { file in
                            attachmentPreview(file: file)
                        }
                    }
                    .padding(.horizontal, Theme.spacing12)
                    .padding(.bottom, Theme.spacing4)
                }
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
                // Text input — standard visible TextEditor with placeholder
                ZStack(alignment: .topLeading) {
                    // Placeholder — offset to match TextEditor's natural text position
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Theme.Typography.body())
                            .foregroundColor(placeholderColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    // Visible TextEditor — uses natural internal padding, cursor aligns with text
                    TextEditor(text: $text)
                        // Lets a UI test name the comment box (task 91a7e180).
                        //
                        // The suite asked for `app.textFields` with a `placeholderValue`
                        // containing "comment", which could never match on two counts: this is a
                        // TextEditor, which XCUITest exposes as a text VIEW, and the placeholder
                        // above is a separate Text so `placeholderValue` is empty. Four tests
                        // skipped with "Comment input field not found" — a sentence about the app
                        // that was really about the query. Exactly the shape that once hid
                        // quick-add, and fixed the same way.
                        //
                        // This is THE comment box on the task detail: the detail mounts it
                        // through `.safeAreaInset(edge: .bottom)`. Two older TextEditors in
                        // `TaskDetailViewNew` and `CommentSectionViewEnhanced` look like the
                        // comment input and are not the one on screen — measured by marking each
                        // placeholder and reading which one the accessibility tree showed.
                        .accessibilityIdentifier(CommentInput.accessibilityIdentifier)
                        .font(Theme.Typography.body())
                        .foregroundColor(textColor)
                        .tint(textColor)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
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

                // Paperclip — three sources, both pickers multi-select (Task a72e09ca).
                Menu {
                    Button { showingPhotoPicker = true } label: {
                        Label(NSLocalizedString("attachments.from_photos", comment: "From Photos"), systemImage: "photo.on.rectangle")
                    }
                    Button { showingDocumentPicker = true } label: {
                        Label(NSLocalizedString("attachments.from_documents", comment: "From Documents"), systemImage: "doc")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingCamera = true } label: {
                            Label(NSLocalizedString("attachments.from_camera", comment: "From Camera"), systemImage: "camera")
                        }
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

                // Send — or timer while the input is empty (task detail)
                if let onTimerTap, !canSend {
                    Button { onTimerTap() } label: {
                        Image(systemName: "timer")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.accent)
                            .padding(10)
                            .background(isOceanTheme ? Color.white : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                } else {
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
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background {
            RoundedRectangle(cornerRadius: Theme.radiusLarge)
                .fill(containerBackgroundColor)
        }
        .onChange(of: isFocused) { _, focused in
            focusReport?.wrappedValue = focused
        }
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        .overlay(alignment: .topLeading) {
            // Autocomplete popup — overlay extends ABOVE the input (negative y offset)
            // Not constrained by parent container bounds
            if showAutocomplete {
                VStack {
                    Spacer()
                    autocompletePopup
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.35)
                }
                .frame(height: UIScreen.main.bounds.height * 0.35 + 8)
                .offset(y: -(UIScreen.main.bounds.height * 0.35 + 8))
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 0)
        .onAppear {
            isFocused = false  // Dismiss keyboard when returning from navigation
            // Pre-fetch list members so @mentions work immediately
            if let listId = listId, ListMemberService.shared.members.isEmpty {
                _Concurrency.Task {
                    try? await ListMemberService.shared.fetchMembers(listId: listId)
                }
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker,
                      selection: $selectedPhotoItems,
                      maxSelectionCount: AttachmentQueue.maxAttachments,
                      matching: .any(of: [.images, .videos]),
                      photoLibrary: .shared())
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            _Concurrency.Task {
                for item in items { await handlePhotoSelection(item) }
                await MainActor.run { selectedPhotoItems = [] }
            }
        }
        .fileImporter(isPresented: $showingDocumentPicker,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                _Concurrency.Task {
                    for url in urls { await handleDocumentSelection(url) }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCapturePicker { image in
                _Concurrency.Task { await handleCapturedPhoto(image) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Computed

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty
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

        guard !content.isEmpty || !attachedFiles.isEmpty else { return }
        guard !isSubmitting else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        let fileIds = attachedFiles.map(\.fileId)
        let messageType: Comment.CommentType = attachedFiles.isEmpty ? .TEXT : .ATTACHMENT

        text = ""
        insertedReferences = []
        attachedFiles = []
        uploadError = nil
        clearAutocomplete()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSend?(content, messageType, fileIds)
    }

    // MARK: - Autocomplete

    private func handleTextChange(_ newValue: String) {
        insertedReferences.removeAll { ref in !newValue.contains(ref.displayText) }
        if let trigger = detectAutocompleteTrigger(in: newValue) {
            print("🔍 [RichTextInput] Trigger detected: type=\(trigger.type), search='\(trigger.search)', text='\(newValue)'")
            activeTrigger = trigger.type
            triggerPosition = trigger.position
            selectedIndex = 0
            let results: [AutocompleteItem]
            switch trigger.type {
            case .mention:
                var users = buildMentionableUsers(listId: listId)
                print("🔍 [RichTextInput] @mention: listId=\(listId ?? "nil"), buildMentionable=\(users.count), agents=\(availableAgents.count), memberService=\(ListMemberService.shared.members.count)")
                for agent in availableAgents where !users.contains(where: { $0.id == agent.id }) {
                    users.append(agent)
                }
                results = filterMentionItems(users: users, search: trigger.search)
                print("🔍 [RichTextInput] @mention results after filter: \(results.count) (users total: \(users.count))")
                // If no users found, try fetching members in background for next trigger
                if results.isEmpty, let listId = listId {
                    print("🔍 [RichTextInput] @mention empty, fetching members for list \(listId)")
                    _Concurrency.Task {
                        try? await ListMemberService.shared.fetchMembers(listId: listId)
                    }
                }
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
    /// One staged file. A compact square rather than a full-width row, because several of
    /// these now sit side by side in a scrolling strip.
    private func attachmentPreview(file: AttachedFileInfo) -> some View {
        let fileExtension: String = file.fileName.components(separatedBy: ".").last?.uppercased() ?? "FILE"

        ZStack(alignment: .topTrailing) {
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
                    VStack(spacing: 2) {
                        Image(systemName: "doc")
                            .font(.system(size: 18))
                            .foregroundColor(mutedTextColor)
                        Text(fileExtension)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(mutedTextColor)
                    }
                }
            }

            Button {
                if file.fileId.hasPrefix("temp_") { attachmentService.cancelUpload(tempFileId: file.fileId) }
                attachedFiles = AttachmentQueue.removing(fileId: file.fileId, from: attachedFiles)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color.black.opacity(0.6))
                    .background(Circle().fill(Color.black.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
        .padding(.top, 8)
    }

    // MARK: - File Handling

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        isUploadingFile = true
        uploadError = nil
        defer { isUploadingFile = false }

        let online = NetworkMonitor.shared.isConnected
        var photoData: Data?
        // No-network PhotoKit read first: on-device photos attach offline,
        // cloud-only photos fail fast with a clear message.
        switch await LocalPhotoLoader.loadImageData(for: item, isConnected: online) {
        case .data(let d):
            photoData = d
        case .notLocallyAvailable:
            uploadError = OfflinePhotoPolicy.unavailableMessage(isConnected: false)
            return
        case .failed:
            // Fallback: some formats only come through the Transferable image path.
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
            uploadError = photoData == nil
                ? OfflinePhotoPolicy.unavailableMessage(isConnected: online)
                : "File size cannot exceed 100MB"
            return
        }

        let fileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        let tempFileId = attachmentService.saveLocallyAndUploadAsync(fileData: data, fileName: fileName, mimeType: "image/jpeg", context: uploadContext)
        attachedFiles = AttachmentQueue.adding(
            AttachedFileInfo(fileId: tempFileId, fileName: fileName, fileSize: data.count, mimeType: "image/jpeg", imageData: data),
            to: attachedFiles)
    }

    /// A photo straight from the camera.
    private func handleCapturedPhoto(_ image: UIImage) async {
        isUploadingFile = true
        uploadError = nil
        defer { isUploadingFile = false }

        guard let data = image.jpegData(compressionQuality: 0.85), data.count <= 100 * 1024 * 1024 else {
            uploadError = "File size cannot exceed 100MB"
            return
        }

        let fileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        let tempFileId = attachmentService.saveLocallyAndUploadAsync(fileData: data, fileName: fileName, mimeType: "image/jpeg", context: uploadContext)
        attachedFiles = AttachmentQueue.adding(
            AttachedFileInfo(fileId: tempFileId, fileName: fileName, fileSize: data.count, mimeType: "image/jpeg", imageData: data),
            to: attachedFiles)
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
        attachedFiles = AttachmentQueue.adding(
            AttachedFileInfo(fileId: tempFileId, fileName: fileName, fileSize: data.count, mimeType: mimeType, imageData: mimeType.hasPrefix("image/") ? data : nil),
            to: attachedFiles)
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
    // Dark: input field = pure black (Theme.Dark.inputBg), container
    // chrome = header-bar tier — the messages/comment composer matches
    // the dark scheme used by the task-list footer and the board.
    private var inputBackgroundColor: Color { effectiveTheme == .dark ? Theme.Dark.inputBg : Color.white }
    private var inputBorderColor: Color { effectiveTheme == .dark ? Theme.Dark.inputBorder : Theme.Ocean.inputBorder }
    @ViewBuilder var containerBackground: some View {
        if effectiveTheme == .light { Rectangle().fill(Theme.LiquidGlass.secondaryGlassMaterial) } else { containerBackgroundColor }
    }
    private var containerBackgroundColor: Color { effectiveTheme == .dark ? Theme.Dark.headerBg : Color.white.opacity(0.8) }
}
