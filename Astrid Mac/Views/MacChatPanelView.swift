//  MacChatPanelView.swift
//  Astrid for Mac — per-list chat (E1, made real-time/paginated/offline-aware in Task 91f2626d).
//  Binds to ChatService.cachedMessages (updated live by SSE handlers), paginates history, and
//  shows pending/failed sends. Send stays offline-first via the shared service.

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacChatPanelView: View {
    let listId: String
    @StateObject private var chat = ChatService.shared
    @StateObject private var auth = AuthManager.shared
    @State private var channelId: String?
    @State private var text = ""
    @State private var loadingMore = false
    @State private var members: [ListMember] = []
    @State private var suggestions: [MacAutocomplete.Suggestion] = []
    @State private var activeHit: MacAutocompleteHit?
    @State private var attaching = false
    @State private var replyingTo: ChatMessage?

    /// Live messages from the observable service cache (SSE + polling keep this fresh).
    private var messages: [ChatMessage] {
        guard let cid = channelId else { return [] }
        return chat.cachedMessages[cid] ?? []
    }
    private var hasMore: Bool { channelId.flatMap { chat.hasMore[$0] } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if hasMore {
                        Button(action: loadEarlier) {
                            if loadingMore { ProgressView().controlSize(.small) }
                            else { Text("Load earlier messages").font(.callout) }
                        }
                        .buttonStyle(.borderless).padding(.vertical, 6)
                    }
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { m in row(m).id(m.id) }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            VStack(spacing: 0) {
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { s in
                            Button { apply(s) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: s.icon).foregroundStyle(Theme.accent)
                                    Text(s.label).lineLimit(1); Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8).padding(.top, 6)
                }
                if let r = replyingTo {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left").foregroundStyle(Theme.accent).font(.caption)
                        Text("Replying to \(r.author?.displayName ?? "message"): \(r.content)")
                            .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Spacer()
                        Button { replyingTo = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                }
                HStack {
                    Button { attachFile() } label: { Image(systemName: "paperclip") }
                        .buttonStyle(.borderless).disabled(channelId == nil || attaching)
                        .help("Attach a file")
                    if attaching { ProgressView().controlSize(.small) }
                    TextField("Message…  (@ mention, # list, ! task)", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                        .onChange(of: text) { updateSuggestions() }
                    Button("Send", action: send).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(8)
            }
        }
        .task(id: listId) { await load() }

    }

    // MARK: autocomplete (@ mention / # list / ! task) — Task cc67a3a5

    private func updateSuggestions() {
        guard let hit = MacAutocomplete.detectTrigger(in: text) else { suggestions = []; activeHit = nil; return }
        activeHit = hit
        // Shared builder (same as task-detail comments) so both inputs behave identically.
        suggestions = MacAutocomplete.suggestions(for: hit, members: members,
                                                  lists: ListService.shared.lists, tasks: TaskService.shared.tasks)
    }

    private func apply(_ s: MacAutocomplete.Suggestion) {
        guard let hit = activeHit else { return }
        text = MacAutocomplete.insert(label: s.label, into: text, hit: hit)
        suggestions = []; activeHit = nil
    }

    /// Attach a file to the channel: read off-main, persist locally + queue upload via the Outbox
    /// (offline-first, same context keys as iOS chat), then send a message referencing it.
    private func attachFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let cid = channelId else { return }
        let name = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        attaching = true
        _Concurrency.Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { await MainActor.run { attaching = false }; return }
            await MainActor.run {
                let fileId = AttachmentService.shared.saveLocallyAndUploadAsync(
                    fileData: data, fileName: name, mimeType: mime, context: ["listId": listId])
                attaching = false
                MacActions.perform("Attach file") {
                    _ = try await chat.sendMessage(channelId: cid, content: name, fileId: fileId)
                }
            }
        }
    }

    private func isPending(_ m: ChatMessage) -> Bool { m.id.hasPrefix("temp_") }

    private func row(_ m: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(m.author?.displayName ?? "Someone").font(.caption).bold().foregroundStyle(Theme.textSecondary)
                if let d = m.createdAt { Text(d, style: .relative).font(.caption2).foregroundStyle(Theme.textMuted) }
                if isPending(m) {
                    Label("Sending…", systemImage: "clock").labelStyle(.titleOnly)
                        .font(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
            Text(m.content).foregroundStyle(Theme.textPrimary)
                .padding(8).background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(isPending(m) ? 0.6 : 1)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.content, forType: .string)
            }
            Button("Reply") { replyingTo = m }
            if MacChatActions.canDelete(authorId: m.authorId, currentUserId: auth.userId, isPending: isPending(m)) {
                Divider()
                Button("Delete", role: .destructive) { deleteMessage(m) }
            }
        }
    }

    private func deleteMessage(_ m: ChatMessage) {
        guard let cid = channelId else { return }
        MacActions.perform("Delete message") { try await chat.deleteMessage(id: m.id, channelId: cid) }
    }

    private func load() async {
        channelId = try? await chat.resolveChannel(forListId: listId)
        try? await ListMemberService.shared.fetchMembers(listId: listId)
        members = ListMemberService.shared.membersByList[listId] ?? []
        guard let cid = channelId else { return }
        _ = try? await chat.fetchMessages(channelId: cid)   // populates the observable cache
    }

    private func loadEarlier() {
        guard let cid = channelId, !loadingMore else { return }
        loadingMore = true
        MacActions.perform("Load messages") {
            defer { loadingMore = false }
            try await chat.loadMoreMessages(channelId: cid)
        }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let cid = channelId else { return }
        // Optimistic/offline-first: the temp message appears immediately; keep the draft until it's accepted.
        let replyId = replyingTo?.id
        MacActions.perform("Send message") {
            _ = try await chat.sendMessage(channelId: cid, content: t, replyToId: replyId)
            text = ""
            replyingTo = nil
        }
    }
}
#endif
