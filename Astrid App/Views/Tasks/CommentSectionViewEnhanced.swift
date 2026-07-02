import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "CommentSection")

/// Enhanced Comment Section with Markdown and SSE support
struct CommentSectionViewEnhanced: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let taskId: String
    var hideInput: Bool = false  // When true, input is handled externally (fixed position)
    @StateObject private var commentService = CommentService.shared
    @StateObject private var attachmentService = AttachmentService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isSubmitting = false
    @State private var replyingTo: Comment?
    // Always use markdown - no toggle needed
    private let useMarkdown = true
    @FocusState private var isTextFieldFocused: Bool
    @State private var showSystemComments = false

    // Attachment state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingVideoPicker = false
    @State private var showingDocumentPicker = false
    @State private var attachedFile: AttachedFileInfo?
    @State private var isUploadingFile = false
    @State private var uploadError: String?

    // Autocomplete state — @mentions, #lists, !tasks (matches ChatInputView)
    @State private var activeTrigger: AutocompleteItem.AutocompleteType?
    @State private var triggerPosition: String.Index?
    @State private var autocompleteItems: [AutocompleteItem] = []
    @State private var insertedReferences: [InsertedReference] = []
    // Legacy mention state kept for compatibility
    @State private var mentionSearch: String?
    @State private var cachedMentionableUsers: [User] = []
    @State private var filteredMentionResults: [User] = []
    @State private var mentionSearchTask: _Concurrency.Task<Void, Never>?

    /// Build the mentionable users list from task and list data
    /// Called once on appear and when task/list data changes
    private func updateMentionableUsers() {
        guard let task = TaskService.shared.tasks.first(where: { $0.id == taskId }) else {
            cachedMentionableUsers = []
            return
        }

        var users: [String: User] = [:]

        if let creator = task.creator {
            users[creator.id] = creator
        }

        if let assignee = task.assignee {
            users[assignee.id] = assignee
        }

        for list in task.lists ?? [] {
            if let fullList = ListService.shared.lists.first(where: { $0.id == list.id }) {
                if let owner = fullList.owner {
                    users[owner.id] = owner
                }
                for member in fullList.members ?? [] {
                    users[member.id] = member
                }
                for admin in fullList.admins ?? [] {
                    users[admin.id] = admin
                }
                for lm in fullList.listMembers ?? [] {
                    if let user = lm.user {
                        users[user.id] = user
                    }
                }
            }
        }

        let currentUserId = AuthManager.shared.userId
        cachedMentionableUsers = Array(users.values).filter { $0.id != currentUserId }
    }

    /// Filter mentionable users with debounce to prevent main thread blocking
    private func filterMentionableUsers(search: String?) {
        // Cancel any pending search
        mentionSearchTask?.cancel()

        guard let search = search, !search.isEmpty else {
            filteredMentionResults = []
            return
        }

        // Debounce: wait 100ms before filtering to batch rapid keystrokes
        mentionSearchTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)  // 100ms

            guard !_Concurrency.Task.isCancelled else { return }

            let lowercasedSearch = search.lowercased()
            let results = cachedMentionableUsers.filter {
                $0.displayName.lowercased().contains(lowercasedSearch) ||
                ($0.email?.lowercased().contains(lowercasedSearch) ?? false)
            }

            await MainActor.run {
                guard !_Concurrency.Task.isCancelled else { return }
                filteredMentionResults = results
            }
        }
    }

    // SSE unsubscribe closures
    @State private var unsubscribeCommentAdded: (@Sendable () -> Void)?
    @State private var unsubscribeCommentUpdated: (@Sendable () -> Void)?
    @State private var unsubscribeCommentDeleted: (@Sendable () -> Void)?
    @State private var unsubscribeTypingStart: (@Sendable () -> Void)?
    @State private var unsubscribeTypingStop: (@Sendable () -> Void)?
    @State private var agentTypingName: String?

    // Computed properties for filtering comments
    private var userComments: [Comment] {
        comments.filter { $0.authorId != nil }
    }

    private var systemComments: [Comment] {
        comments.filter { $0.authorId == nil }
    }

    private var displayedComments: [Comment] {
        // When offline, show all comments regardless of authorId
        // (cached comments may not have authorId populated due to caching bug)
        if !networkMonitor.isConnected {
            return comments
        }
        return showSystemComments ? comments : userComments
    }

    private var displayedCommentCount: Int {
        // When offline, show all comments
        if !networkMonitor.isConnected {
            return comments.count
        }
        return showSystemComments ? comments.count : userComments.count
    }

    private var allTaskFiles: [SecureFile] {
        var files: [SecureFile] = []
        
        // 1. Add direct task attachments
        if let task = TaskService.shared.tasks.first(where: { $0.id == taskId }) {
            if let taskFiles = task.secureFiles {
                files.append(contentsOf: taskFiles)
            }
            
            // 2. Add legacy attachments
            if let legacyAttachments = task.attachments {
                for att in legacyAttachments {
                    files.append(SecureFile(
                        id: att.id,
                        name: att.name,
                        size: att.size,
                        mimeType: att.type
                    ))
                }
            }
        }
        
        // 3. Add files from all comments (using CommentService cache)
        if let taskComments = CommentService.shared.cachedComments[taskId] {
            for comment in taskComments {
                if let commentFiles = comment.secureFiles {
                    files.append(contentsOf: commentFiles)
                }
            }
        }
        
        // 4. Remove duplicates by ID
        var uniqueFiles: [SecureFile] = []
        var seenIds = Set<String>()
        for file in files {
            if !seenIds.contains(file.id) {
                uniqueFiles.append(file)
                seenIds.insert(file.id)
            }
        }
        
        return uniqueFiles
    }

    private func insertMention(_ user: User) {
        guard let lastAtRange = newCommentText.range(of: "@", options: .backwards) else { return }

        let mentionText = "@[\(user.displayName)](\(user.id)) "
        newCommentText = newCommentText.replacingCharacters(in: lastAtRange.lowerBound..<newCommentText.endIndex, with: mentionText)
        mentionSearch = nil
    }

    // MARK: - Autocomplete (@ # !)

    private func detectCommentTrigger(in text: String) {
        let triggerChars: [(Character, AutocompleteItem.AutocompleteType)] = [
            ("@", .mention), ("#", .list), ("!", .task),
        ]

        var bestTrigger: AutocompleteItem.AutocompleteType?
        var bestPos: String.Index?
        var bestSearch: String = ""

        for (char, type) in triggerChars {
            guard let idx = text.lastIndex(of: char) else { continue }
            if idx != text.startIndex {
                let charBefore = text[text.index(before: idx)]
                if !charBefore.isWhitespace && charBefore != "\n" { continue }
            }
            let afterTrigger = String(text[text.index(after: idx)...])
            if afterTrigger.contains(" ") || afterTrigger.contains("\n") { continue }
            if bestPos == nil || idx > bestPos! {
                bestTrigger = type
                bestPos = idx
                bestSearch = afterTrigger
            }
        }

        if let trigger = bestTrigger, let pos = bestPos {
            activeTrigger = trigger
            triggerPosition = pos
            filterCommentAutocomplete(type: trigger, search: bestSearch)
        } else {
            clearCommentAutocomplete()
        }
    }

    private func filterCommentAutocomplete(type: AutocompleteItem.AutocompleteType, search: String) {
        let results: [AutocompleteItem]
        switch type {
        case .mention:
            results = filterCommentMentions(search: search)
        case .list:
            results = filterCommentLists(search: search)
        case .task:
            results = filterCommentTasks(search: search)
        }
        autocompleteItems = results
    }

    private func filterCommentMentions(search: String) -> [AutocompleteItem] {
        // Use existing cachedMentionableUsers + AI agents
        var users = cachedMentionableUsers
        if let agents = AIAgentCache.shared.load() {
            let currentUserId = AuthManager.shared.userId
            for agent in agents where agent.id != currentUserId && !users.contains(where: { $0.id == agent.id }) {
                users.append(agent)
            }
        }
        let lowered = search.lowercased()
        let filtered = lowered.isEmpty ? users : users.filter {
            $0.displayName.lowercased().contains(lowered) ||
            ($0.email?.lowercased().contains(lowered) ?? false)
        }
        return filtered.map { user in
            AutocompleteItem(
                id: user.id, type: .mention, label: user.displayName,
                secondaryLabel: user.email, image: user.image,
                isAIAgent: user.isAIAgent == true, isShared: false, privacy: nil, completed: false
            )
        }
    }

    private func filterCommentLists(search: String) -> [AutocompleteItem] {
        let lists = ListService.shared.lists.filter { $0.isVirtual != true }
        let lowered = search.lowercased()
        let filtered = lowered.isEmpty ? lists : lists.filter { $0.name.lowercased().contains(lowered) }
        return Array(filtered.prefix(10)).map { list in
            let isShared = list.privacy == .SHARED || list.privacy == .PUBLIC
            return AutocompleteItem(
                id: list.id, type: .list, label: list.name,
                secondaryLabel: list.privacy?.rawValue.capitalized, image: nil,
                isAIAgent: false, isShared: isShared, privacy: list.privacy?.rawValue, completed: false
            )
        }
    }

    private func filterCommentTasks(search: String) -> [AutocompleteItem] {
        let allTasks = TaskService.shared.tasks
        let lowered = search.lowercased()
        var filtered = lowered.isEmpty ? allTasks : allTasks.filter { $0.title.lowercased().contains(lowered) }
        filtered.sort { a, b in
            if a.completed != b.completed { return !a.completed }
            return (a.updatedAt ?? a.createdAt ?? .distantPast) > (b.updatedAt ?? b.createdAt ?? .distantPast)
        }
        return Array(filtered.prefix(15)).map { task in
            let listName = task.lists?.first?.name ?? task.listIds?.compactMap { id in
                ListService.shared.lists.first(where: { $0.id == id })?.name
            }.first
            return AutocompleteItem(
                id: task.id, type: .task, label: task.title,
                secondaryLabel: listName, image: nil,
                isAIAgent: false, isShared: false, privacy: nil, completed: task.completed
            )
        }
    }

    private func insertAutocompleteItem(_ item: AutocompleteItem) {
        guard let pos = triggerPosition else { return }
        let displayText = "\(item.triggerChar)\(item.label)"
        let textBefore = String(newCommentText[newCommentText.startIndex..<pos])
        newCommentText = textBefore + displayText + " "
        insertedReferences.append(InsertedReference(id: item.id, type: item.type, displayText: displayText))
        clearCommentAutocomplete()
    }

    private func clearCommentAutocomplete() {
        activeTrigger = nil
        triggerPosition = nil
        autocompleteItems = []
    }

    /// Reconstruct @[Name](id) format from display text
    private func reconstructReferences(in text: String) -> String {
        var result = text
        let sorted = insertedReferences.sorted { $0.displayText.count > $1.displayText.count }
        for ref in sorted {
            let fullRef = "\(ref.displayText.prefix(1))[\(ref.displayText.dropFirst())](\(ref.id))"
            if let range = result.range(of: ref.displayText) {
                result = result.replacingCharacters(in: range, with: fullRef)
            }
        }
        return result
    }

    private func pruneCommentReferences() {
        insertedReferences.removeAll { ref in !newCommentText.contains(ref.displayText) }
    }


    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            // Header (show even when offline)
            HStack {
                Text(String(format: NSLocalizedString("comments.count", comment: "Comments count"), displayedCommentCount))
                    .font(Theme.Typography.headline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                if !systemComments.isEmpty {
                    Button(action: {
                        showSystemComments.toggle()
                    }) {
                        Text(showSystemComments ? "Hide system" : "Show system")
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }

                Spacer()

                // Show offline indicator if not connected
                if !networkMonitor.isConnected {
                    HStack(spacing: Theme.spacing4) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12))
                        Text("Offline")
                            .font(Theme.Typography.caption2())
                    }
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }

                if commentService.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(0.8)
                }
            }

            // Comments list
            if displayedComments.isEmpty {
                Text(NSLocalizedString("comments.empty", comment: "No comments yet. Be the first to comment!"))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .padding(.vertical, Theme.spacing8)
            } else {
                // Use comment.id directly - must ensure all comments have valid IDs
                ForEach(displayedComments, id: \.stableId) { comment in
                    CommentRowViewEnhanced(
                        comment: comment,
                        allTaskFiles: allTaskFiles,
                        colorScheme: colorScheme,
                        useMarkdown: useMarkdown,
                        isOffline: !networkMonitor.isConnected,
                        onReply: {
                            replyingTo = comment
                            isTextFieldFocused = true
                        },
                        onDelete: {
                            // Remove comment from UI immediately
                            comments.removeAll { $0.id == comment.id }
                        }
                    )
                }
            }

            // New comment input (offline sync supported via optimistic updates)
            // Agent typing indicator
            if let typingName = agentTypingName {
                AgentTypingIndicator(agentName: typingName)
            }

            // When hideInput is true, input is handled externally (fixed position above keyboard)
            if !hideInput {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                // Autocomplete popup — @mentions, #lists, !tasks
                if activeTrigger != nil && !autocompleteItems.isEmpty {
                    AutocompletePopupView(
                        items: autocompleteItems,
                        activeTrigger: activeTrigger,
                        textColor: colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary,
                        mutedColor: colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted,
                        backgroundColor: colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary,
                        borderColor: colorScheme == .dark ? Theme.Dark.inputBorder : Theme.inputBorder,
                        onSelect: { item in insertAutocompleteItem(item) },
                        onDismiss: { clearCommentAutocomplete() }
                    )
                }

                if let replyingTo = replyingTo {
                    HStack {
                        Text("Replying to \(replyingTo.author?.displayName ?? "Unknown")")
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                        Spacer()

                        Button("Cancel") {
                            self.replyingTo = nil
                        }
                        .font(Theme.Typography.caption1())
                        .foregroundColor(Theme.accent)
                    }
                    .padding(.horizontal, Theme.spacing12)
                    .padding(.vertical, Theme.spacing8)
                    .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                }

                // File attachment preview - thumbnail for images, compact card for others
                if let file = attachedFile {
                    HStack(alignment: .bottom, spacing: Theme.spacing8) {
                        // Thumbnail or file icon
                        ZStack(alignment: .topTrailing) {
                            if file.isImage, let imageData = file.imageData, let uiImage = UIImage(data: imageData) {
                                // Image thumbnail
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                            } else {
                                // File icon for non-images
                                ZStack {
                                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                        .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                                        .frame(width: 64, height: 64)

                                    VStack(spacing: 4) {
                                        Image(systemName: fileIcon(for: file.mimeType))
                                            .font(.system(size: 24))
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                                        Text(file.fileName.components(separatedBy: ".").last?.uppercased() ?? "FILE")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    }
                                }
                            }

                            // X button overlay
                            Button {
                                // Cancel pending upload if still in progress
                                if file.fileId.hasPrefix("temp_") {
                                    attachmentService.cancelUpload(tempFileId: file.fileId)
                                }
                                attachedFile = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                            }
                            .offset(x: 6, y: -6)
                        }

                        Spacer()
                    }
                }

                HStack(alignment: .bottom, spacing: Theme.spacing8) {
                    // Expandable comment input with @/#/! autocomplete
                    ZStack(alignment: .topLeading) {
                        // Hidden sizing text
                        Text(newCommentText.isEmpty ? " " : newCommentText)
                            .font(Theme.Typography.body())
                            .foregroundColor(.clear)
                            .padding(Theme.spacing12)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Placeholder text
                        if newCommentText.isEmpty {
                            Text("Add a comment...")
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                .padding(Theme.spacing12)
                                .allowsHitTesting(false)
                        }

                        // TextEditor — visible text, standard behavior
                        TextEditor(text: $newCommentText)
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, Theme.spacing8)
                            .padding(.vertical, Theme.spacing4)
                            .focused($isTextFieldFocused)
                            .onChange(of: newCommentText) { _, newValue in
                                detectCommentTrigger(in: newValue)
                                pruneCommentReferences()
                            }
                    }
                    .frame(minHeight: 44, maxHeight: 200)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .simultaneousGesture(
                        DragGesture().onChanged { value in
                            if value.translation.height > 10 {
                                isTextFieldFocused = false
                            }
                        }
                    )

                    // Attachment menu button with paperclip icon
                    Menu {
                        // Photo picker option
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label(NSLocalizedString("attachments.choose_photo", comment: "Choose Photo"), systemImage: "photo")
                        }

                        // Video picker option
                        Button {
                            showingVideoPicker = true
                        } label: {
                            Label(NSLocalizedString("attachments.choose_video", comment: "Choose Video"), systemImage: "video")
                        }

                        // Document picker option
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label(NSLocalizedString("attachments.choose_document", comment: "Choose Document"), systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: isUploadingFile ? "arrow.up.circle" : "paperclip")
                            .font(.system(size: 16))
                            .foregroundColor(isUploadingFile ? .gray : Theme.accent)
                            .padding(10)
                            .background(themeMode == "ocean" ? Color.white : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingFile || isSubmitting)

                    Button {
                        _Concurrency.Task { await submitComment() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(Theme.accent)
                                .padding(10)
                                .background(themeMode == "ocean" ? Color.white : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.accent)
                                .padding(10)
                                .background(themeMode == "ocean" ? Color.white : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled((newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedFile == nil) || isSubmitting)
                }
            }
            } // end if !hideInput
        }
        .task {
            // Cache mentionable users on first load
            updateMentionableUsers()
            await loadComments()
            await subscribeToSSE()
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            if newValue && !oldValue {
                // Connection restored - sync pending comments first, then reload
                _Concurrency.Task {
                    print("🔄 [CommentSection] Network restored - syncing pending comments...")
                    await retryPendingComments()
                    await subscribeToSSE()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commentDidSync)) { notification in
            // Only reload if notification is for this task (or no taskId specified for backwards compat)
            if let notificationTaskId = notification.userInfo?["taskId"] as? String {
                guard notificationTaskId == taskId else { return }
            }
            // Reload comments after sync/refresh completes
            _Concurrency.Task {
                await loadComments()
            }
        }
        .onDisappear {
            unsubscribeFromSSE()
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            guard let photoItem = newValue else { return }
            _Concurrency.Task {
                await uploadPhotoItem(photoItem)
            }
        }
        .onChange(of: selectedVideoItem) { oldValue, newValue in
            guard let videoItem = newValue else { return }
            _Concurrency.Task {
                await uploadVideoItem(videoItem)
            }
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.pdf, .plainText, .zip, .image, .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi, UTType(filenameExtension: "doc")!, UTType(filenameExtension: "docx")!, UTType(filenameExtension: "mkv")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                _Concurrency.Task {
                    await uploadDocument(url)
                }
            case .failure(let error):
                print("❌ Document picker error: \(error)")
                uploadError = "Failed to select document: \(error.localizedDescription)"
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .photosPicker(
            isPresented: $showingVideoPicker,
            selection: $selectedVideoItem,
            matching: .videos,
            photoLibrary: .shared()
        )
        .alert(NSLocalizedString("comments.upload_error", comment: "Upload Error"), isPresented: .init(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) {
            Button("OK", role: .cancel) {
                uploadError = nil
            }
        } message: {
            if let error = uploadError {
                Text(error)
            }
        }
    }

    private func loadComments() async {
        logger.notice("loadComments: taskId=\(self.taskId.prefix(8), privacy: .public), current=\(self.comments.count, privacy: .public)")

        // Keep track of our local comments (for merging)
        // Use uniquingKeysWith to safely handle duplicate IDs (can occur with corrupted data)
        let localComments = Dictionary(comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pendingComments = comments.filter { $0.id.hasPrefix("temp_") }

        do {
            let fetchedComments = try await commentService.fetchComments(taskId: taskId, useCache: true)
            logger.notice("✅ Fetched \(fetchedComments.count, privacy: .public) comments")

            // Build merged list: use fetched comments, but prefer local data for existing ones
            var mergedComments: [Comment] = []

            for var fetched in fetchedComments {

                // If we have local version with better data, use it
                if let local = localComments[fetched.id] {
                    // Keep local secureFiles if server didn't return them
                    if (fetched.secureFiles == nil || fetched.secureFiles?.isEmpty == true),
                       let localFiles = local.secureFiles, !localFiles.isEmpty {
                        fetched.secureFiles = localFiles
                    }
                    // Keep local author if server didn't return it
                    if fetched.author == nil, let localAuthor = local.author {
                        fetched.author = localAuthor
                        fetched.authorId = localAuthor.id
                    }
                }
                mergedComments.append(fetched)
            }

            // Add pending comments that haven't synced yet
            for pending in pendingComments {
                // Check if it synced - use multiple criteria for robust matching:
                // 1. Same content AND similar time (within 5 minutes to handle clock skew)
                // 2. OR same author AND similar time (for attachment-only comments with empty content)
                let synced = fetchedComments.contains { fetched in
                    let timeDiff = abs((fetched.createdAt ?? Date()).timeIntervalSince(pending.createdAt ?? Date()))
                    let timeMatches = timeDiff < 300 // 5 minutes to handle clock skew

                    // Content match (handles text comments)
                    let contentMatches = fetched.content == pending.content && !fetched.content.isEmpty

                    // Author + time match (handles attachment-only comments)
                    let authorMatches = fetched.authorId == pending.authorId && pending.authorId != nil

                    return (contentMatches && timeMatches) || (authorMatches && timeMatches && fetched.content == pending.content)
                }
                if !synced {
                    mergedComments.append(pending)
                    print("📝 [CommentSection] Keeping pending comment: \(pending.id.prefix(20))")
                } else {
                    print("✅ [CommentSection] Pending comment synced: \(pending.id.prefix(20))")
                }
            }

            // Sort by createdAt to maintain correct order (pending comments may have earlier timestamps)
            mergedComments.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

            comments = mergedComments
            logger.notice("✅ Final: \(self.comments.count, privacy: .public) comments")
        } catch {
            logger.error("❌ loadComments failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func subscribeToSSE() async {
        // Skip SSE subscription when offline
        guard networkMonitor.isConnected else {
            print("📵 [CommentSection] Skipping SSE subscription - device is offline")
            return
        }

        print("📡 [CommentSection] Subscribing to SSE events for task \(taskId)")

        // Subscribe to comment events and store unsubscribe closures
        unsubscribeCommentAdded = await SSEClient.shared.onCommentAdded { [taskId] comment, relatedTaskId in
            guard relatedTaskId == taskId else { return }
            print("✅ [CommentSection] SSE comment_added: \(comment.id)")
            _Concurrency.Task { @MainActor in
                // Skip if we already have this comment
                if comments.contains(where: { $0.id == comment.id }) {
                    print("⚠️ [CommentSection] Skipping duplicate: \(comment.id)")
                    return
                }

                // Clear typing indicator if agent comment arrived
                if comment.author?.isAIAgent == true {
                    agentTypingName = nil
                }

                // Check if this is a synced version of a temp comment (match by content)
                if let index = comments.firstIndex(where: { $0.id.hasPrefix("temp_") && $0.content == comment.content }) {
                    // Just update the ID - keep our local data (author, secureFiles, etc.)
                    comments[index].id = comment.id
                    print("✅ [CommentSection] Updated temp → real ID: \(comment.id)")
                } else {
                    // Truly new comment from another user/device
                    comments.append(comment)
                    print("✅ [CommentSection] Added new comment: \(comment.id)")
                }
            }
        }

        unsubscribeCommentUpdated = await SSEClient.shared.onCommentUpdated { [taskId] comment, relatedTaskId in
            guard relatedTaskId == taskId else { return }
            print("✅ [CommentSection] SSE comment_updated: \(comment.id)")
            _Concurrency.Task { @MainActor in
                if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                    // Only update content - keep our local secureFiles, author, etc.
                    comments[index].content = comment.content
                    comments[index].updatedAt = comment.updatedAt
                    print("✅ [CommentSection] Updated content for: \(comment.id)")
                }
            }
        }

        unsubscribeCommentDeleted = await SSEClient.shared.onCommentDeleted { [taskId] commentId, relatedTaskId in
            guard relatedTaskId == taskId else {
                print("🔕 [CommentSection] Ignoring comment_deleted for different task (got \(relatedTaskId), want \(taskId))")
                return
            }
            print("✅ [CommentSection] Received comment_deleted for task \(taskId)")
            _Concurrency.Task { @MainActor in
                let beforeCount = comments.count
                comments.removeAll { $0.id == commentId }
                let afterCount = comments.count
                if beforeCount > afterCount {
                    print("✅ [CommentSection] Removed comment from UI: \(commentId)")
                } else {
                    print("⚠️ [CommentSection] Comment not found for deletion: \(commentId)")
                }
            }
        }

        // Typing indicators for task comments
        unsubscribeTypingStart = await SSEClient.shared.onAgentTypingStart { [taskId] agentName, _, eventTaskId in
            guard eventTaskId == taskId else { return }
            _Concurrency.Task { @MainActor in
                self.agentTypingName = agentName
            }
        }

        unsubscribeTypingStop = await SSEClient.shared.onAgentTypingStop { [taskId] _, eventTaskId in
            guard eventTaskId == taskId else { return }
            _Concurrency.Task { @MainActor in
                self.agentTypingName = nil
            }
        }

        print("✅ [CommentSection] SSE subscriptions registered")
    }

    private func unsubscribeFromSSE() {
        print("📡 [CommentSection] Unsubscribing from SSE events for task \(taskId)")

        unsubscribeCommentAdded?()
        unsubscribeCommentUpdated?()
        unsubscribeCommentDeleted?()
        unsubscribeTypingStart?()
        unsubscribeTypingStop?()

        unsubscribeCommentAdded = nil
        unsubscribeCommentUpdated = nil
        unsubscribeCommentDeleted = nil
        unsubscribeTypingStart = nil
        unsubscribeTypingStop = nil

        print("✅ [CommentSection] SSE subscriptions cleaned up")
    }

    private func submitComment() async {
        print("🚀 [CommentSection] submitComment() called, network: \(networkMonitor.isConnected)")

        let trimmedText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || attachedFile != nil else {
            print("⚠️ [CommentSection] Empty comment and no attachment - skipping")
            return
        }

        print("📋 [CommentSection] Content: '\(trimmedText.prefix(30))...', hasAttachment: \(attachedFile != nil)")

        // Determine comment type based on attachment or markdown
        let commentType: Comment.CommentType
        if attachedFile != nil {
            commentType = .ATTACHMENT
        } else if useMarkdown {
            commentType = .MARKDOWN
        } else {
            commentType = .TEXT
        }

        // Reconstruct @[Name](id), #[Name](id), ![Name](id) from display text
        let commentContent = reconstructReferences(in: trimmedText)
        insertedReferences = []

        // OPTIMISTIC UPDATE: Create and show comment immediately
        let tempId = "temp_\(UUID().uuidString)"

        // Build author from all available sources - currentUser, UserDefaults, or fallback
        let userId = AuthManager.shared.userId ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userId) ?? "me"
        let userName = AuthManager.shared.currentUser?.name
            ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userName)
        let userEmail = AuthManager.shared.currentUser?.email
            ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userEmail)
        let userImage = AuthManager.shared.currentUser?.image
            ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userImage)

        // Use "Me" as fallback name if we have no user info at all
        let displayName = userName ?? userEmail ?? "Me"

        let author = User(
            id: userId,
            email: userEmail,
            name: displayName,  // Always have a name
            image: userImage
        )

        print("📝 [Comment] Creating optimistic comment with author: \(author.displayName), image: \(author.image ?? "none")")

        let optimisticComment = Comment(
            id: tempId,
            content: commentContent,
            type: commentType,
            authorId: author.id,
            author: author,
            taskId: taskId,
            createdAt: Date(),
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: attachedFile?.fileName,
            attachmentType: attachedFile?.mimeType,
            attachmentSize: attachedFile?.fileSize,
            parentCommentId: replyingTo?.id,
            replies: nil,
            secureFiles: attachedFile != nil ? [SecureFile(id: attachedFile!.fileId, name: attachedFile!.fileName, size: attachedFile!.fileSize, mimeType: attachedFile!.mimeType)] : nil
        )

        // Add to UI immediately
        let replyToId = replyingTo?.id
        if let replyToId = replyToId {
            // Add as reply
            if let index = comments.firstIndex(where: { $0.id == replyToId }) {
                if comments[index].replies == nil {
                    comments[index].replies = []
                }
                comments[index].replies?.append(optimisticComment)
            }
        } else {
            // Add as top-level comment
            comments.append(optimisticComment)
        }

        // Store fileId before clearing (we need it for the API call)
        var fileIdToSend = attachedFile?.fileId
        print("🔍 [CommentSection] Initial fileIdToSend: \(fileIdToSend ?? "nil")")

        // If fileId is a temp ID, try to get the real fileId
        if let tempFileId = fileIdToSend, tempFileId.hasPrefix("temp_") {
            let isOnline = networkMonitor.isConnected
            let hasRealId = attachmentService.getRealFileId(for: tempFileId) != nil
            let isPending = attachmentService.isPendingUpload(tempFileId)
            print("🔍 [CommentSection] Temp fileId check: online=\(isOnline), hasRealId=\(hasRealId), isPending=\(isPending)")

            if let realFileId = attachmentService.getRealFileId(for: tempFileId) {
                // Upload already complete, use real ID
                fileIdToSend = realFileId
            } else if !isOnline || OutboxConfig.sourceOfTruthEnabled {
                // OFFLINE — or Outbox-authoritative, where the upload only STARTS
                // when the comment is enqueued (upload→comment chain), so waiting
                // here would deadlock: keep the temp fileId, the chain resolves it.
                // fileIdToSend stays as tempFileId
            } else if isPending {
                // Online (legacy) - upload in progress, wait for it (max 60s).
                // On timeout fall back to the temp id — NEVER nil, which would
                // post an attachment comment with no attachment (HTTP 400).
                fileIdToSend = await waitForUploadCompletion(tempFileId: tempFileId) ?? tempFileId
            }
        }
        print("✅ [CommentSection] Final fileIdToSend: \(fileIdToSend ?? "nil")")

        // Clear input immediately (feels instant!)
        newCommentText = ""
        attachedFile = nil
        replyingTo = nil
        isTextFieldFocused = false
        clearCommentAutocomplete()

        isSubmitting = true

        // Create comment via service - this saves to CoreData and triggers background sync
        // The service returns an optimistic comment immediately; sync happens in background
        // When sync completes, .commentDidSync notification will trigger reload
        do {
            _ = try await commentService.createComment(
                taskId: taskId,
                content: optimisticComment.content,
                type: commentType,
                fileId: fileIdToSend,
                parentCommentId: optimisticComment.parentCommentId,
                authorId: author.id
            )

            // Comment created and sync started
            // The .commentDidSync notification will update UI when sync completes
            print("✅ [CommentSection] Comment created, sync in progress...")

        } catch {
            print("❌ [CommentSection] Failed to create comment: \(error)")

            // DON'T remove the comment - keep it as pending
            // The CommentService already saved it to CoreData with pending status
            // It will sync when network is restored or user triggers retry
            print("📵 [CommentSection] Comment kept as pending - will sync when online")
        }

        isSubmitting = false
    }

    /// Retry syncing all pending comments and attachments
    private func retryPendingComments() async {
        guard networkMonitor.isConnected else {
            print("📵 [CommentSection] Cannot retry - no network connection")
            return
        }

        print("🔄 [CommentSection] Retrying pending uploads and comments...")

        do {
            // First sync any pending attachments (comments may depend on them)
            await attachmentService.syncPendingUploads()

            // Retry any failed comment operations
            await commentService.retryFailedOperations()

            // Then sync all pending comments
            try await commentService.syncPendingComments()

            // Reload to get updated IDs
            await loadComments()
        } catch {
            print("❌ [CommentSection] Retry failed: \(error)")
        }
    }

    // MARK: - File Upload Helpers

    // Maximum file size: 100 MB
    private let maxFileSize = 100 * 1024 * 1024

    private func uploadPhotoItem(_ photoItem: PhotosPickerItem) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            print("📸 [CommentSection] Starting photo upload... (network: \(networkMonitor.isConnected))")

            // Load via PhotoKit with a no-network read first so an on-device photo
            // attaches instantly even offline, and a cloud-only photo offline fails
            // fast (instead of hanging on a doomed iCloud download).
            let imageData: Data
            switch await LocalPhotoLoader.loadImageData(for: photoItem, isConnected: networkMonitor.isConnected) {
            case .data(let data):
                imageData = data
            case .notLocallyAvailable:
                await MainActor.run { uploadError = OfflinePhotoPolicy.unavailableMessage(isConnected: false) }
                return
            case .failed:
                print("❌ [CommentSection] Failed to load image data from PhotosPicker")
                await MainActor.run {
                    uploadError = OfflinePhotoPolicy.unavailableMessage(isConnected: networkMonitor.isConnected)
                }
                return
            }

            print("📸 [CommentSection] Photo loaded: \(formatFileSize(imageData.count))")

            // Check file size
            if imageData.count > maxFileSize {
                print("❌ [CommentSection] Photo too large: \(formatFileSize(imageData.count)) (max 100 MB)")
                await MainActor.run {
                    uploadError = "Photo is too large (\(formatFileSize(imageData.count))). Maximum size is 100 MB. For larger files, please upload to a file service (Google Drive, Dropbox, etc.) and share a link instead."
                }
                return
            }

            // Get filename
            let fileName = "photo_\(UUID().uuidString).jpg"
            let mimeType = "image/jpeg"

            // Save locally and start async upload - returns immediately with temp fileId
            let tempFileId = attachmentService.saveLocallyAndUploadAsync(
                fileData: imageData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: taskId
            )

            print("📸 [CommentSection] Photo saved locally, uploading in background: \(tempFileId)")

            // Set attached file immediately (no waiting for upload!)
            // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: imageData.count,
                    mimeType: mimeType,
                    imageData: imageData  // For thumbnail preview
                )

                // Pre-cache thumbnail for when comment is posted
                // Already on MainActor, so UIImage(data:) is safe here
                if let uiImage = UIImage(data: imageData) {
                    ThumbnailCache.shared.set(uiImage, for: tempFileId)
                    print("📸 [CommentSection] Thumbnail cached for: \(tempFileId)")
                }

                print("📸 [CommentSection] attachedFile set: fileId=\(tempFileId), size=\(imageData.count)")
            }

        } catch {
            print("❌ [CommentSection] Failed to load photo: \(error)")
            await MainActor.run {
                uploadError = "Failed to load photo: \(error.localizedDescription)"
            }
        }

        // Clear selection
        await MainActor.run {
            selectedPhotoItem = nil
        }
    }

    private func uploadVideoItem(_ videoItem: PhotosPickerItem) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            print("🎥 [CommentSection] Starting video upload...")

            // Load video data
            guard let videoData = try await videoItem.loadTransferable(type: Data.self) else {
                print("❌ [CommentSection] Failed to load video data from PhotosPicker")
                await MainActor.run {
                    uploadError = "Failed to load video. Please try again."
                }
                return
            }

            print("🎥 [CommentSection] Video loaded: \(formatFileSize(videoData.count))")

            // Check file size
            if videoData.count > maxFileSize {
                print("❌ [CommentSection] Video too large: \(formatFileSize(videoData.count)) (max 100 MB)")
                await MainActor.run {
                    uploadError = "Video is too large (\(formatFileSize(videoData.count))). Maximum size is 100 MB. For larger files, please upload to a file service (Google Drive, Dropbox, etc.) and share a link instead."
                }
                return
            }

            // Get filename and mime type
            let fileName = "video_\(UUID().uuidString).mp4"
            let mimeType = "video/mp4"

            // Save locally and start async upload - returns immediately with temp fileId
            let tempFileId = attachmentService.saveLocallyAndUploadAsync(
                fileData: videoData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: taskId
            )

            print("🎥 [CommentSection] Video saved locally, uploading in background: \(tempFileId)")

            // Set attached file immediately (no waiting for upload!)
            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: videoData.count,
                    mimeType: mimeType,
                    imageData: nil  // No thumbnail for videos
                )
            }

        } catch {
            print("❌ [CommentSection] Failed to load video: \(error)")
            await MainActor.run {
                uploadError = "Failed to load video: \(error.localizedDescription)"
            }
        }

        // Clear selection
        await MainActor.run {
            selectedVideoItem = nil
        }
    }

    private func uploadDocument(_ url: URL) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            // Access the file
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ [CommentSection] Failed to access document at: \(url.path)")
                await MainActor.run {
                    uploadError = "Failed to access document. Please try again."
                }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // Read file data
            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let mimeType = attachmentService.getMimeType(for: url.pathExtension)

            // Check file size
            if fileData.count > maxFileSize {
                print("❌ [CommentSection] Document too large: \(formatFileSize(fileData.count)) (max 100 MB)")
                await MainActor.run {
                    uploadError = "Document is too large (\(formatFileSize(fileData.count))). Maximum size is 100 MB. For larger files, please upload to a file service (Google Drive, Dropbox, etc.) and share a link instead."
                }
                return
            }

            // Save locally and start async upload - returns immediately with temp fileId
            let tempFileId = attachmentService.saveLocallyAndUploadAsync(
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: taskId
            )

            // Set attached file immediately (no waiting for upload!)
            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: fileData.count,
                    mimeType: mimeType,
                    imageData: nil  // No thumbnail for documents
                )
            }

        } catch {
            print("❌ [CommentSection] Failed to load document: \(error)")
            await MainActor.run {
                uploadError = "Failed to load document: \(error.localizedDescription)"
            }
        }
    }

    private func fileIcon(for mimeType: String) -> String {
        let lowercased = mimeType.lowercased()

        if lowercased.hasPrefix("image/") {
            return "photo"
        } else if lowercased.hasPrefix("video/") {
            return "video"
        } else if lowercased.hasPrefix("audio/") {
            return "waveform"
        } else if lowercased.contains("pdf") {
            return "doc.text"
        } else if lowercased.contains("zip") || lowercased.contains("archive") {
            return "archivebox"
        } else {
            return "doc"
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Wait for a pending attachment upload to complete
    private func waitForUploadCompletion(tempFileId: String) async -> String? {
        // Use class-based state to safely share mutable state across closures
        final class State: @unchecked Sendable {
            var observer: NSObjectProtocol?
            var hasResumed = false
        }
        let state = State()

        return await withCheckedContinuation { continuation in
            // Set a timeout of 60 seconds
            let timeoutTask = _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: 60_000_000_000)

                // Check if cancelled or already resumed before proceeding
                guard !_Concurrency.Task.isCancelled && !state.hasResumed else {
                    return
                }

                state.hasResumed = true
                if let obs = state.observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                print("⏰ [CommentSection] Upload timeout for: \(tempFileId)")
                continuation.resume(returning: nil)
            }

            state.observer = NotificationCenter.default.addObserver(
                forName: .attachmentUploadCompleted,
                object: nil,
                queue: .main
            ) { notification in
                guard let userInfo = notification.userInfo,
                      let notificationTempId = userInfo["tempFileId"] as? String,
                      notificationTempId == tempFileId,
                      let realFileId = userInfo["realFileId"] as? String else {
                    return
                }

                // Guard against double-resume
                guard !state.hasResumed else {
                    return
                }
                state.hasResumed = true

                // Cancel timeout
                timeoutTask.cancel()

                // Remove observer
                if let obs = state.observer {
                    NotificationCenter.default.removeObserver(obs)
                }

                print("✅ [CommentSection] Upload completed, got fileId: \(realFileId)")
                continuation.resume(returning: realFileId)
            }
        }
    }
}

struct CommentRowViewEnhanced: View {
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let comment: Comment
    let allTaskFiles: [SecureFile]
    let colorScheme: ColorScheme
    let useMarkdown: Bool
    let isOffline: Bool  // When offline, treat all cached comments as user comments
    let onReply: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteAlert = false

    // Effective theme
    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    // Check if this comment is from the current user
    private var isCurrentUser: Bool {
        comment.authorId == AuthManager.shared.userId
    }

    // Check if this is a system comment (no authorId)
    private var isSystemComment: Bool {
        if isOffline {
            return false
        }
        return comment.authorId == nil
    }

    // Check if comment has text content (not just attachments)
    private var hasTextContent: Bool {
        !comment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Background color for current user's comments
    private var currentUserBubbleBackground: Color {
        if effectiveTheme == "ocean" {
            return Color.white
        } else if effectiveTheme == "dark" {
            return Theme.Dark.bgSecondary
        } else {
            return Theme.bgSecondary
        }
    }

    // Background color for other users' comments
    @ViewBuilder
    private var otherUserBubbleBackground: some View {
        if effectiveTheme == "ocean" {
            Color.white.opacity(0.5)
        } else if effectiveTheme == "light" {
            Rectangle().fill(Theme.LiquidGlass.primaryGlassMaterial)
        } else {
            Theme.Dark.bgPrimary
        }
    }

    // Context menu for comment actions (reusable)
    private var commentContextMenu: some View {
        Group {
            Button {
                UIPasteboard.general.string = comment.content
            } label: {
                Label(NSLocalizedString("actions.copy", comment: "Copy"), systemImage: "doc.on.doc")
            }

            Button {
                onReply()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }

            if isCurrentUser {
                Divider()
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label(NSLocalizedString("actions.delete", comment: "Delete"), systemImage: "trash")
                }
            }
        }
    }

    var body: some View {
        // System comments use discreet formatting
        if isSystemComment {
            Text(comment.createdAt != nil ? "On \(formatSystemCommentDate(comment.createdAt!)), \(comment.content)" : comment.content)
                .font(Theme.Typography.caption2())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
        } else {
            // Chat-style comment layout
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Theme.spacing4) {
                HStack(alignment: .center, spacing: Theme.spacing8) {
                    // Left avatar (other users only)
                    if !isCurrentUser {
                        avatarView
                    } else {
                        Spacer(minLength: 48)
                    }

                    // Message bubble (long press for options)
                    VStack(alignment: .leading, spacing: hasTextContent ? Theme.spacing8 : 0) {
                        // Attachments - tap opens preview, long press shows context menu
                        if let secureFiles = comment.secureFiles, !secureFiles.isEmpty {
                            ChatAttachmentView(
                                files: secureFiles,
                                allTaskFiles: allTaskFiles,
                                colorScheme: colorScheme,
                                contextMenuContent: { commentContextMenu }
                            )
                        }

                        // Content
                        // Content — with colored @mentions, #lists, !tasks
                        if hasTextContent {
                            Text(comment.content.attributedWithReferences(
                                defaultColor: colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary
                            ))
                            .font(Theme.Typography.body())
                        }

                        // Pending indicator removed - comments sync automatically in background
                        // The temp ID prefix indicates pending status internally
                    }
                    // More padding for attachment-only comments to give tap area for context menu
                    .padding(hasTextContent ? Theme.spacing12 : Theme.spacing16)
                    .background(
                        Group {
                            if isCurrentUser {
                                currentUserBubbleBackground
                            } else {
                                otherUserBubbleBackground
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .contentShape(Rectangle()) // Ensure entire bubble responds to long press
                    .contextMenu { commentContextMenu }

                    // Right avatar (current user only)
                    if isCurrentUser {
                        avatarView
                    } else {
                        Spacer(minLength: 48)
                    }
                }

                // Name and timestamp below bubble (also tappable for context menu)
                // For current user: right-aligned with bubble edge (not avatar)
                // For other users: left-aligned with bubble edge (not avatar)
                HStack(spacing: Theme.spacing4) {
                    if isCurrentUser {
                        Spacer()
                    } else {
                        // Spacer to align with bubble start (after avatar)
                        Spacer().frame(width: 40)
                    }

                    Text(isCurrentUser ? NSLocalizedString("assignee.you", comment: "You") : (comment.author?.displayName ?? "Unknown"))
                        .font(Theme.Typography.caption2())
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                    if let createdAt = comment.createdAt {
                        Text("·")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        Text(formatCommentDate(createdAt))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }

                    if isCurrentUser {
                        // Spacer to align with bubble end (before avatar)
                        Spacer().frame(width: 40)
                    } else {
                        Spacer()
                    }
                }
                .contentShape(Rectangle()) // Make timestamp row tappable
                .contextMenu { commentContextMenu }

                // Replies
                if let replies = comment.replies, !replies.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        ForEach(replies) { reply in
                            CommentRowViewEnhanced(
                                comment: reply,
                                allTaskFiles: allTaskFiles,
                                colorScheme: colorScheme,
                                useMarkdown: useMarkdown,
                                isOffline: isOffline,
                                onReply: onReply,
                                onDelete: onDelete
                            )
                        }
                    }
                    .padding(.top, Theme.spacing4)
                }
            }
            .alert(NSLocalizedString("comments.delete_comment", comment: "Delete Comment"), isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    _Concurrency.Task {
                        do {
                            onDelete()
                            try await CommentService.shared.deleteComment(id: comment.id)
                        } catch {
                            print("❌ Delete comment failed: \(error)")
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this comment?")
            }
        }
    }

    // Avatar view (reusable for both sides)
    // For current user: use locally cached image (no network fetch needed)
    // For other users: use CachedAsyncImage with their profile URL
    private var avatarView: some View {
        NavigationLink(destination: UserProfileView(userId: comment.authorId ?? "")) {
            Group {
                if isCurrentUser {
                    // Current user: use locally cached image from AuthManager/UserDefaults
                    let imageURL = AuthManager.shared.currentUser?.image
                        ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userImage)
                    let initials = AuthManager.shared.currentUser?.initials
                        ?? comment.author?.initials
                        ?? "?"

                    CachedAsyncImage(url: imageURL.flatMap { URL(string: $0) }) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            Circle()
                                .fill(Theme.accent)
                            Text(initials)
                                .font(Theme.Typography.caption1())
                                .foregroundColor(Theme.accentText)
                        }
                    }
                } else {
                    // Other users: use their cached image URL
                    CachedAsyncImage(url: comment.author?.cachedImageURL.flatMap { URL(string: $0) }) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            Circle()
                                .fill(Theme.accent)
                            Text(comment.author?.initials ?? "?")
                                .font(Theme.Typography.caption1())
                                .foregroundColor(Theme.accentText)
                        }
                    }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Types

/// File info response for secure file downloads
private struct SecureFileInfo: Codable {
    let url: String
}

// MARK: - Helper Functions

private func formatCommentDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()

    // Check if date is today
    if calendar.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    // Check if date is this year
    if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    // Date from previous year
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy, h:mm a"
    return formatter.string(from: date)
}

private func formatSystemCommentDate(_ date: Date) -> String {
    // Format: "Nov 19 at 6:30 PM" (compact format for system comments)
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d 'at' h:mm a"
    return formatter.string(from: date)
}

/// Simplified attachment view for chat-style comments - images display naturally without grey box
struct ChatAttachmentView<MenuContent: View>: View {
    let files: [SecureFile]
    let allTaskFiles: [SecureFile]
    let colorScheme: ColorScheme
    @ViewBuilder let contextMenuContent: () -> MenuContent

    @State private var selectedIndex: Int = 0
    @State private var isShowingQuickLook = false
    @State private var previewItems: [(fileId: String, url: URL)] = []
    @State private var isPreparingPreview = false

    private let maxWidth: CGFloat = 220
    private let maxHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(files, id: \.id) { file in
                ChatAttachmentItem(
                    file: file,
                    colorScheme: colorScheme,
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                    onTap: { prepareAndShowPreview(for: file) },
                    contextMenuContent: contextMenuContent
                )
            }
        }
        .quickLookPresenter(items: previewItems, initialIndex: selectedIndex, isPresented: $isShowingQuickLook)
        .overlay {
            if isPreparingPreview {
                ProgressView().tint(Theme.accent)
            }
        }
    }

    private func prepareAndShowPreview(for file: SecureFile) {
        isPreparingPreview = true
        _Concurrency.Task {
            let results = await AttachmentService.shared.prepareFilesForPreview(files: allTaskFiles)
            await MainActor.run {
                self.previewItems = results
                if let index = results.firstIndex(where: { $0.fileId == file.id }) {
                    self.selectedIndex = index
                } else {
                    self.selectedIndex = 0
                }
                self.isPreparingPreview = false
                if !previewItems.isEmpty {
                    self.isShowingQuickLook = true
                }
            }
        }
    }
}

/// Single attachment item for chat - images render naturally, documents show icon
/// Tap opens preview, long press shows context menu
struct ChatAttachmentItem<MenuContent: View>: View {
    let file: SecureFile
    let colorScheme: ColorScheme
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let onTap: () -> Void
    @ViewBuilder let contextMenuContent: () -> MenuContent

    @StateObject private var attachmentService = AttachmentService.shared
    @State private var image: UIImage?
    @State private var isLoading = false

    private var isImage: Bool {
        file.mimeType.lowercased().hasPrefix("image/")
    }

    private var isVideo: Bool {
        file.mimeType.lowercased().hasPrefix("video/")
    }

    var body: some View {
        Group {
            if isImage || isVideo {
                // Image/video: display naturally with rounded corners, no grey box
                ZStack {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                        // Video play icon
                        if isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(radius: 2)
                        }
                    } else if isLoading {
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .fill(Color.clear)
                            .frame(width: 100, height: 100)
                            .overlay(ProgressView().tint(Theme.accent))
                    } else {
                        // Placeholder while loading
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: isVideo ? "video" : "photo")
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            )
                    }
                }
            } else {
                // Documents: show compact file info
                HStack(spacing: Theme.spacing8) {
                    Image(systemName: fileIcon)
                        .font(.system(size: 24))
                        .foregroundColor(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(Theme.Typography.caption1())
                            .lineLimit(1)
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        Text(formatFileSize(file.size))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
                .padding(Theme.spacing8)
                .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu { contextMenuContent() }
        .task(id: file.id) {
            if (isImage || isVideo) && image == nil {
                await loadImage()
            }
        }
    }

    private func loadImage() async {
        // Check cache first
        if let cached = ThumbnailCache.shared.get(file.id) {
            image = cached
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Check if local temp file
        if file.id.hasPrefix("temp_") {
            if let localData = attachmentService.getLocalFileData(for: file.id) {
                let img = await MainActor.run { UIImage(data: localData) }
                if let img {
                    image = img
                    ThumbnailCache.shared.set(img, for: file.id)
                }
            }
            return
        }

        // Check disk cache
        if let cachedData = attachmentService.getCachedDownload(for: file.id) {
            let img = await MainActor.run { UIImage(data: cachedData) }
            if let img {
                image = img
                ThumbnailCache.shared.set(img, for: file.id)
                return
            }
        }

        // Download from server
        do {
            let infoURL = "\(Constants.API.baseURL)/api/v1/secure-files/\(file.id)?info=true"
            guard let url = URL(string: infoURL) else { return }

            var request = URLRequest(url: url)
            if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            }

            let (infoData, infoResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = infoResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }

            let fileInfo = try JSONDecoder().decode(SecureFileInfo.self, from: infoData)
            guard let downloadURL = URL(string: fileInfo.url) else { return }

            let (fileData, _) = try await URLSession.shared.data(from: downloadURL)
            let img = await MainActor.run { UIImage(data: fileData) }
            if let img {
                image = img
                ThumbnailCache.shared.set(img, for: file.id)
                attachmentService.cacheDownload(fileId: file.id, data: fileData)
            }
        } catch {
            print("❌ [ChatAttachmentItem] Failed to load image: \(error)")
        }
    }

    private var fileIcon: String {
        let mimeType = file.mimeType.lowercased()
        if mimeType.contains("pdf") { return "doc.text" }
        else if mimeType.contains("zip") || mimeType.contains("archive") { return "archivebox" }
        else if mimeType.hasPrefix("audio/") { return "waveform" }
        else { return "doc" }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        CommentSectionViewEnhanced(taskId: "sample-task-id")
            .padding()
    }
}
