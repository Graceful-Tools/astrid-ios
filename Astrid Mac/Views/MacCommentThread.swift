//  MacCommentThread.swift
//  Astrid for Mac — the comment thread and its composer, shared by every surface that shows a
//  task's comments (Task AITD-432).
//
//  The list view's task details and the board card each had their own. Every comment feature
//  landed in the details — ⌘V attaches (AITD-306), Send (AITD-303), stage-then-post (3b3d70ce),
//  @-autocomplete (eda86d23), a comment draws its files (AITD-304) and is markdown (AITD-389) —
//  and the board card got none of them, because it was a second implementation nobody opened.
//  Jon found it by pasting a screenshot on the board and watching nothing happen.
//
//  So there is one draft model, one composer and one thread here, and both surfaces draw them.
//  A comment feature added to this file reaches both; one added to a surface is the drift
//  `MacBoardCommentParityTests` exists to catch.

#if os(macOS)
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - The draft

/// The comment being written: its text, the files staged on it, the autocomplete state, and the
/// three ways a file gets in (paperclip, ⌘V, the ⋯ menu's Add file). Owned by the surface as a
/// `@StateObject` so that surface's menu can reach the same picker the paperclip opens.
@MainActor
final class MacCommentDraft: ObservableObject {
    @Published var text = ""
    /// Files picked but not yet posted (task 3b3d70ce). Rendered as previews above the field;
    /// nothing reaches the server as a comment until Post.
    @Published var stagedFiles: [AttachedFileInfo] = []
    @Published private(set) var suggestions: [MacAutocomplete.Suggestion] = []
    private var hit: MacAutocompleteHit?

    // MARK: autocomplete (eda86d23)

    func updateSuggestions(members: [ListMember]) {
        guard let found = MacAutocomplete.detectTrigger(in: text) else { clearSuggestions(); return }
        hit = found
        suggestions = MacAutocomplete.suggestions(for: found, members: members,
                                                  lists: ListService.shared.lists,
                                                  tasks: TaskService.shared.tasks)
    }

    func applySuggestion(_ s: MacAutocomplete.Suggestion) {
        guard let hit else { return }
        text = MacAutocomplete.insert(label: s.label, into: text, hit: hit)
        clearSuggestions()
    }

    private func clearSuggestions() { suggestions = []; hit = nil }

    // MARK: staging

    /// STAGE a file on the comment being written (task 3b3d70ce).
    ///
    /// This used to post immediately, with the filename as the body — so the paperclip meant
    /// "post a comment that is a file" rather than "attach to this comment". You could not see
    /// what you had picked, and you could not say anything alongside it. The board card kept
    /// doing exactly that until AITD-432 gave it this picker.
    ///
    /// The upload still starts now rather than on send: it is offline-first and returns a temp
    /// id straight away, so by the time you press Post the bytes are usually already gone. What
    /// changed is only WHEN the comment is created.
    func attachComment(taskId: String) {
        guard !AttachmentQueue.isFull(stagedFiles) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        _Concurrency.Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = try? Data(contentsOf: url) else { return }
            await MainActor.run {
                guard let self else { return }
                let fileId = AttachmentService.shared.saveLocallyAndUploadAsync(
                    fileData: data, fileName: name, mimeType: mime, taskId: taskId)
                // The SHARED queue owns the cap and the duplicate rule. Its header records why:
                // hand-rolling this got "pick a second file" wrong once already, and the first
                // pick vanished silently.
                self.stagedFiles = AttachmentQueue.adding(
                    AttachedFileInfo(fileId: fileId, fileName: name, fileSize: data.count,
                                     mimeType: mime,
                                     imageData: mime.hasPrefix("image/") ? data : nil),
                    to: self.stagedFiles)
            }
        }
    }

    /// Without this a mis-picked file could only be got rid of by posting it.
    func removeStaged(_ file: AttachedFileInfo) {
        if file.fileId.hasPrefix("temp_") {
            AttachmentService.shared.cancelUpload(tempFileId: file.fileId)
        }
        stagedFiles = AttachmentQueue.removing(fileId: file.fileId, from: stagedFiles)
    }

    // MARK: paste to attach (AITD-306)

    /// Returns true when this ⌘V was turned into a staged attachment — the caller then consumes
    /// the event. Every other ⌘V is left alone so text still pastes.
    func handlePaste(_ event: NSEvent, commentFocused: Bool, taskId: String) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command],
              event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
        guard !AttachmentQueue.isFull(stagedFiles) else { return false }
        let candidates = MacCommentPaste.candidates(from: Self.pasteboardSnapshot(), now: Date())
        // A text editor other than the comment field owns its own ⌘V — the title and the notes
        // are still plain text paste.
        let otherEditor = !commentFocused
            && (NSApp.keyWindow?.firstResponder is NSText
                || NSApp.keyWindow?.firstResponder is NSTextView)
        guard MacCommentPaste.handlesPaste(hasAttachableContent: !candidates.isEmpty,
                                           commentFieldFocused: commentFocused,
                                           otherEditorFocused: otherEditor) else { return false }
        stagedFiles = MacCommentPaste.staged(candidates, onto: stagedFiles) { candidate in
            // Same call the paperclip makes: offline-first, returns a temp id immediately, and
            // the Outbox carries the bytes. Nothing is posted until Send.
            AttachmentService.shared.saveLocallyAndUploadAsync(
                fileData: candidate.data, fileName: candidate.name,
                mimeType: candidate.mimeType, taskId: taskId)
        }
        return true
    }

    /// Read the general pasteboard into the pure `Snapshot` the rules work on.
    ///
    /// File URLs first — a file copied in Finder puts BOTH a URL and an image rendition on the
    /// board, and the file keeps the real name and the original bytes. `.png` is preferred over
    /// `.tiff` for a nameless rendition because a screenshot is already PNG and the TIFF is a
    /// much larger re-encode of the same pixels.
    private static func pasteboardSnapshot() -> MacCommentPaste.Snapshot {
        let pb = NSPasteboard.general
        let urls = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let files: [MacCommentPaste.Candidate] = urls.compactMap { url in
            // A folder has no bytes to attach, and `Data(contentsOf:)` on one throws.
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let data = try? Data(contentsOf: url) else { return nil }
            return MacCommentPaste.file(named: url.lastPathComponent, data: data)
        }
        if !files.isEmpty { return MacCommentPaste.Snapshot(files: files) }
        if let png = pb.data(forType: .png) {
            return MacCommentPaste.Snapshot(imageData: png, imageExtension: "png")
        }
        if let tiff = pb.data(forType: .tiff) {
            // Re-encode to PNG: a pasted TIFF is several times the size for the same pixels, and
            // the thumbnail path and the server both prefer PNG.
            let encoded = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            return MacCommentPaste.Snapshot(imageData: encoded ?? tiff,
                                            imageExtension: encoded == nil ? "tiff" : "png")
        }
        return MacCommentPaste.Snapshot()
    }

    // MARK: posting

    /// Post the text and the staged files, then hand back to the surface to refresh its thread.
    func addComment(taskId: String, onPosted: @escaping @MainActor () async -> Void) {
        let c = text.trimmingCharacters(in: .whitespaces)
        // Either text or a staged file is enough to post; neither is not.
        guard MacCommentSend.canPost(text: c, stagedCount: stagedFiles.count) else { return }
        clearSuggestions()
        // The SHARED splitter. The comments endpoint takes a single fileId, so several files
        // become several comments — with the typed text on the FIRST only, since repeating a
        // caption under every photo reads as a stutter. iOS sends through this same function.
        let drafts = CommentAttachmentBatch.drafts(text: c,
                                                   fileIds: stagedFiles.map(\.fileId),
                                                   useMarkdown: false)
        guard !drafts.isEmpty else { return }
        let author = MacCommentPost.authorId(currentUserId: AuthManager.shared.userId)
        // Keep the draft until the post succeeds; surface failures instead of losing the text.
        AppActions.perform("Post comment") { [weak self] in
            // One at a time so they land in the order they were picked.
            for draft in drafts {
                _ = try await CommentService.shared.createComment(
                    taskId: taskId, content: draft.content,
                    fileId: draft.fileId, authorId: author)
            }
            self?.text = ""
            self?.stagedFiles = []
            await onPosted()
        }
    }
}

// MARK: - The composer

/// The Add-a-comment bar: autocomplete above, the staged strip, then paperclip · field · the
/// surface's accessory (a running timer's clock) · Send, or the surface's idle button when there
/// is nothing to send.
struct MacCommentComposerBar<Accessory: View, Idle: View>: View {
    @ObservedObject var draft: MacCommentDraft
    let taskId: String
    let members: [ListMember]
    var focus: FocusState<Bool>.Binding
    let onPosted: @MainActor () async -> Void
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var idle: () -> Idle

    /// ⌘V with a screenshot or a file on the clipboard attaches it to the comment (AITD-306).
    /// A local monitor rather than `.onPasteCommand`: the comment field is an NSTextField, and it
    /// swallows `paste:` whether or not it found a string to insert — so an image paste never
    /// reached a SwiftUI paste modifier at all.
    @State private var pasteMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if !draft.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(draft.suggestions) { s in
                        Button { draft.applySuggestion(s) } label: {
                            Label(s.label, systemImage: s.icon).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .macHoverHighlight()
                    }
                }
                .background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
            }
            stagedAttachments
            HStack(spacing: 8) {
                Button { draft.attachComment(taskId: taskId) } label: { Image(systemName: "paperclip") }
                    .buttonStyle(.borderless).help(NSLocalizedString("mac.attach_file", comment: ""))
                    .disabled(AttachmentQueue.isFull(draft.stagedFiles))
                TextField(NSLocalizedString("comments.add_placeholder", comment: ""), text: $draft.text)
                    .textFieldStyle(.plain)
                    .focused(focus)
                    .onChange(of: draft.text) { draft.updateSuggestions(members: members) }
                    .onSubmit(addComment)
                accessory()
                // The trailing slot becomes Send as soon as there is something to send (AITD-303).
                // Return already posted; nothing said so, and a staged screenshot had no visible
                // way out.
                if MacCommentSend.showsSend(text: draft.text, stagedCount: draft.stagedFiles.count) {
                    Button(action: addComment) { Image(systemName: "paperplane.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.accent)
                        .macPointingHand()
                        .help(NSLocalizedString("chat.send", comment: ""))
                        .accessibilityIdentifier("comment.send")
                } else {
                    idle()
                }
            }
            .padding(10)
        }
        .onAppear(perform: installPasteMonitor)
        .onDisappear(perform: removePasteMonitor)
    }

    private func addComment() {
        draft.addComment(taskId: taskId, onPosted: onPosted)
    }

    /// Watch for ⌘V while this composer is on screen. The event is CONSUMED only when the paste
    /// is going to attach something; every other ⌘V is handed straight back so text still pastes.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard draft.handlePaste(event, commentFocused: focus.wrappedValue, taskId: taskId) else {
                return event
            }
            // Attaching implies you meant to comment; put the caret where the caption goes.
            focus.wrappedValue = true
            return nil
        }
    }

    private func removePasteMonitor() {
        if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil }
    }

    /// The staged files, above the comment field — a strip, since several can be queued.
    @ViewBuilder private var stagedAttachments: some View {
        if !draft.stagedFiles.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draft.stagedFiles, id: \.fileId) { file in
                        ZStack(alignment: .topTrailing) {
                            if file.isImage, let data = file.imageData, let image = NSImage(data: data) {
                                Image(nsImage: image)
                                    .resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6).fill(Theme.bgSecondary)
                                        .frame(width: 56, height: 56)
                                    VStack(spacing: 2) {
                                        Image(systemName: "doc").font(.system(size: 18))
                                        // A file extension, not prose — verbatim so the hardcoded-string guard passes it deliberately.
                                        Text(verbatim: file.fileName.components(separatedBy: ".").last?.uppercased() ?? "FILE")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundStyle(Theme.textMuted)
                                }
                            }
                            Button { draft.removeStaged(file) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                            .help(NSLocalizedString("actions.remove", comment: ""))
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.top, 8)
            }
        }
    }
}

// MARK: - The thread

/// "Comments (N)" · show/hide system comments · Refresh.
struct MacCommentsHeader: View {
    let comments: [Comment]
    @Binding var showSystem: Bool
    let isOffline: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Text(String(format: NSLocalizedString("mac.comments_count", comment: ""),
                        CommentVisibility.count(comments, showSystem: showSystem, isOffline: isOffline)))
            if MacSystemComments.showsToggle(comments, isOffline: isOffline) {
                Button(MacSystemComments.toggleTitle(showingSystem: showSystem)) { showSystem.toggle() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Button(action: onRefresh) {
                Label(NSLocalizedString("mac.refresh", comment: ""), systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless).font(.caption)
        }
    }
}

/// The comments themselves. Its body is a list of rows, so it sits inside a Form `Section` in the
/// details and inside a plain `VStack` on the board card alike.
///
/// System comments ("marked complete", "moved to …") are hidden until asked for — iOS parity
/// (CommentSectionViewEnhanced, 9c24d16c) — and a repeating task's completion lines fold into one
/// streak row (dd3fda86).
struct MacCommentThreadList: View {
    @Binding var comments: [Comment]
    let taskId: String
    let showSystem: Bool
    let isOffline: Bool
    @Binding var profileTarget: MacProfileTarget?
    /// Open one of a comment's files. The surface owns the Quick Look presentation.
    let onPreviewFile: (SecureFile) -> Void
    /// Edit one of your own comments. The surface owns the sheet.
    let onEdit: (Comment) -> Void

    @State private var expandedStreaks: Set<String> = []

    var body: some View {
        if comments.isEmpty {
            Text(NSLocalizedString("mac.no_comments", comment: "")).foregroundStyle(Theme.textMuted).font(.callout)
        }
        ForEach(CompletionStreak.fold(
            CommentVisibility.displayed(comments, showSystem: showSystem, isOffline: isOffline))) { item in
            switch item {
            case .comment(let c):
                commentBubble(c)
            case .streak(let streak):
                streakRow(streak)
            }
        }
    }

    /// Web-style comment bubble (df22157f): own comments right-aligned in a lavender card with an
    /// avatar and a "You · date" caption; others left-aligned with the author's name.
    ///
    /// The bubble also draws the comment's OWN files (AITD-304). It used to draw `c.content` and
    /// nothing else, so a file posted without a caption arrived as an empty pill — which is what
    /// "the attachment is broken" turned out to mean: it attached, and nothing ever showed it.
    @ViewBuilder private func commentBubble(_ c: Comment) -> some View {
        // One shared decision for every surface that shows an author (283a03df).
        let who = MacAuthorDisplay.of(c, currentUser: AuthManager.shared.currentUser)
        let mine = who.isCurrentUser
        let files = MacCommentBubble.attachments(of: c)
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 30) }
                if !mine { commentAvatar(who, authorId: c.authorId) }
                VStack(alignment: .leading, spacing: 6) {
                    if !files.isEmpty {
                        MacCommentAttachmentsView(files: files) { onPreviewFile($0) }
                    }
                    // No text, no text bubble — an empty pill under a photo reads as a failure.
                    if MacCommentBubble.showsText(c.content) {
                        // A comment is markdown, like a description and like the web bubble these
                        // are usually read in (AITD-389) — same renderer, hugging its text so the
                        // bubble stays the size of what was said.
                        MacMarkdownText(source: c.content, fillsWidth: false)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Theme.accent.opacity(0.12) : Theme.bgSecondary,
                            in: RoundedRectangle(cornerRadius: 12))
                if mine { commentAvatar(who, authorId: c.authorId) }
                if !mine { Spacer(minLength: 30) }
            }
            HStack(spacing: 4) {
                // Names open the profile, as on iOS. System comments have no id and stay plain.
                Text(who.name).macOpensProfile(c.authorId, target: $profileTarget)
                if let d = c.createdAt { Text("·"); Text(d, style: .relative) }
            }
            .font(.caption2).foregroundStyle(Theme.textMuted)
            .padding(mine ? .trailing : .leading, 30)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .contentShape(Rectangle())
        .contextMenu {
            // Edit/Delete only your own comments (permission-safe).
            if mine {
                Button(NSLocalizedString("actions.edit", comment: "")) { onEdit(c) }
                Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { deleteComment(c) }
            }
        }
    }

    /// A folded run of completions (dd3fda86) — one line, expanding to the actual dates on click.
    @ViewBuilder private func streakRow(_ streak: CompletionStreak.Streak) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(MacMotion.fast) {
                    if expandedStreaks.contains(streak.id) { expandedStreaks.remove(streak.id) }
                    else { expandedStreaks.insert(streak.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.accent)
                    Text(CompletionStreak.summary(for: streak))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: expandedStreaks.contains(streak.id) ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textMuted)
                }
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).macPointingHand()

            if expandedStreaks.contains(streak.id) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(streak.dates, id: \.self) { date in
                        Text(date, format: .dateTime.month().day().hour().minute())
                            .font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The photo opens the profile too — people click the face at least as often as the name.
    private func commentAvatar(_ who: MacAuthorDisplay, authorId: String?) -> some View {
        MacAuthorAvatar(display: who, size: 20)
            .macOpensProfile(authorId, target: $profileTarget)
    }

    private func deleteComment(_ c: Comment) {
        AppActions.perform("Delete comment") {
            try await CommentService.shared.deleteComment(id: c.id)
            comments = (try? await CommentService.shared.fetchComments(taskId: taskId)) ?? []
        }
    }

    // MARK: shared actions the surfaces call

    /// Save an edited comment and refresh the thread.
    static func saveEdit(of c: Comment, text: String, taskId: String,
                         into comments: Binding<[Comment]>) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != c.content else { return }
        AppActions.perform("Edit comment") {
            _ = try await CommentService.shared.updateComment(id: c.id, content: trimmed)
            comments.wrappedValue = (try? await CommentService.shared.fetchComments(taskId: taskId)) ?? []
        }
    }

    /// Open a comment's file in Quick Look (AITD-304). The SHARED preparer resolves the bytes —
    /// a still-uploading staged file from the local copy, anything else from the cache or the
    /// server — so a photo can be opened full size the moment it is posted, offline included.
    static func previewURL(for file: SecureFile) async -> URL? {
        await AttachmentService.shared.prepareFilesForPreview(files: [file]).first?.url
    }
}

/// Small reusable edit sheet for a single text value — a comment, a subtask's title.
struct MacTextEditSheet: View {
    let title: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField("", text: $text, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
                .macTextSelection()
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: ""), action: onCancel).keyboardShortcut(.escape, modifiers: [])
                Button(NSLocalizedString("actions.save", comment: ""), action: onSave).buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 360)
    }
}
#endif
