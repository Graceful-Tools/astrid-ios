//  MacChatPanelView.swift
//  Astrid for Mac — per-list chat (E1, made real-time/paginated/offline-aware in Task 91f2626d).
//  Binds to ChatService.cachedMessages (updated live by SSE handlers), paginates history, and
//  shows pending/failed sends. Send stays offline-first via the shared service.

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacChatPanelView: View {
    let source: MacChatSource
    @AppStorage(MacScrollBars.defaultsKey) private var showScrollBars = false
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
    @State private var agentTypingName: String?     // "… is thinking" indicator (eb1b7da6)
    @State private var unsubscribeTyping: [() -> Void] = []
    @State private var loadingChannel = false       // first-load spinner (1c3562e9)

    /// Live messages from the observable service cache (SSE + polling keep this fresh).
    private var messages: [ChatMessage] {
        guard let cid = channelId else { return [] }
        return chat.cachedMessages[cid] ?? []
    }
    private var hasMore: Bool { channelId.flatMap { chat.hasMore[$0] } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            // Loading + branded empty states (1c3562e9) via the tested surface rule (e4d0eb84).
            switch MacChatLoadState.surface(loading: loadingChannel, hasMessages: !messages.isEmpty) {
            case .spinner:
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(NSLocalizedString("mac.loading_messages", comment: "")).font(.caption).foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                MacEmptyState(copy: .chatEmpty)
            case .messages:
            ScrollViewReader { proxy in
                ScrollView {
                    if hasMore {
                        Button(action: loadEarlier) {
                            if loadingMore { ProgressView().controlSize(.small) }
                            else { Text(NSLocalizedString("chat.load_earlier", comment: "")).font(.callout) }
                        }
                        .buttonStyle(.borderless).padding(.vertical, 6)
                    }
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { m in row(m).id(m.id) }
                        if let name = agentTypingName {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("\(name) is thinking…").font(.caption).foregroundStyle(Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                }
                .macScrollBars(showScrollBars)
                .onChange(of: messages.count) {
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
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
                            }
                            .buttonStyle(.plain)
                            .macHoverHighlight()
                            .macPointingHand()
                        }
                    }
                    .background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8).padding(.top, 6)
                }
                if let r = replyingTo {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left").foregroundStyle(Theme.accent).font(.caption)
                        Text(String(format: NSLocalizedString("mac.replying_to", comment: ""), r.author?.displayName ?? "message", r.content))
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
                        .help(NSLocalizedString("mac.attach_file", comment: ""))
                    if attaching { ProgressView().controlSize(.small) }
                    TextField(NSLocalizedString("mac.message_placeholder", comment: ""), text: $text)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                        .onChange(of: text) { updateSuggestions() }
                    Button(NSLocalizedString("chat.send", comment: ""), action: send).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(8)
            }
        }
        .task(id: source) { await load() }
        .onDisappear { unsubscribeTyping.forEach { $0() }; unsubscribeTyping = [] }

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
                    fileData: data, fileName: name, mimeType: mime, context: source.listIdForMembers.map { ["listId": $0] } ?? [:])
                attaching = false
                MacActions.perform("Attach file") {
                    _ = try await chat.sendMessage(channelId: cid, content: name, fileId: fileId)
                }
            }
        }
    }

    private func isPending(_ m: ChatMessage) -> Bool { m.id.hasPrefix("temp_") }

    /// Small initials avatar for others' messages; agents get a purple sparkles badge look.
    @ViewBuilder private func chatAvatar(_ m: ChatMessage, isAgent: Bool) -> some View {
        ZStack {
            Circle().fill(isAgent ? Color.purple.opacity(0.8) : Theme.accent)
            if isAgent {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            } else {
                Text(m.author?.initials ?? "?").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }

    /// Web/iOS-style bubble row (eb1b7da6): mine right-aligned in accent, agents purple with a
    /// sparkles badge + avatar, others left with an initials avatar; @/#/! references colored via
    /// the SHARED attributedWithReferences.
    private func row(_ m: ChatMessage) -> some View {
        let mine = MacChatBubbleStyle.isMine(authorId: m.authorId, currentUserId: auth.userId)
        let agent = m.isFromAgent
        return HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 40) }
            if MacChatBubbleStyle.showsAvatar(isMine: mine) { chatAvatar(m, isAgent: agent) }
            VStack(alignment: MacChatBubbleStyle.alignment(isMine: mine), spacing: 2) {
                HStack(spacing: 4) {
                    if !mine {
                        Text(m.author?.displayName ?? "Someone").font(.caption).bold().foregroundStyle(Theme.textSecondary)
                        if agent {
                            Image(systemName: "sparkles").font(.caption2).foregroundStyle(.purple)
                        }
                    }
                    if let d = m.createdAt { Text(d, style: .relative).font(.caption2).foregroundStyle(Theme.textMuted) }
                    if isPending(m) {
                        Label(NSLocalizedString("mac.sending", comment: ""), systemImage: "clock").labelStyle(.titleOnly)
                            .font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
                Text(m.content.attributedWithReferences(defaultColor: Theme.textPrimary))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(MacChatBubbleStyle.fill(isMine: mine, isAgent: agent))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(isPending(m) ? 0.6 : 1)
            }
            if !mine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .contentShape(Rectangle())
        .macHoverHighlight()   // hover affordance surfaces the context-menu interactivity (77225941)
        .contextMenu {
            Button(NSLocalizedString("actions.copy", comment: "")) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.content, forType: .string)
            }
            Button(NSLocalizedString("mac.reply", comment: "")) { replyingTo = m }
            if MacChatActions.canDelete(authorId: m.authorId, currentUserId: auth.userId, isPending: isPending(m)) {
                Divider()
                Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { deleteMessage(m) }
            }
        }
    }

    private func deleteMessage(_ m: ChatMessage) {
        guard let cid = channelId else { return }
        MacActions.perform("Delete message") { try await chat.deleteMessage(id: m.id, channelId: cid) }
    }

    private func load() async {
        loadingChannel = true
        switch source {
        case .list(let id):
            channelId = try? await chat.resolveChannel(forListId: id)
            try? await ListMemberService.shared.fetchMembers(listId: id)
            members = ListMemberService.shared.membersByList[id] ?? []
        case .virtual(let key):
            // My Tasks and friends: same channel iOS and web resolve. No list members to mention.
            channelId = try? await chat.resolveVirtualChannel(virtualKey: key)
            members = []
        }
        guard let cid = channelId else { loadingChannel = false; return }
        _ = try? await chat.fetchMessages(channelId: cid)   // populates the observable cache
        // Spinner clears DETERMINISTICALLY here (e4d0eb84) — it must never wait on the SSE actor.
        loadingChannel = false

        // Agent typing indicator (eb1b7da6): subscribe OFF the load path — awaiting the SSE actor
        // here used to wedge load() (and the spinner) whenever the actor was busy streaming.
        _Concurrency.Task { @MainActor in
            unsubscribeTyping.forEach { $0() }
            let start = await SSEClient.shared.onAgentTypingStart { agentName, eventChannelId, _ in
                guard eventChannelId == cid else { return }
                _Concurrency.Task { @MainActor in agentTypingName = agentName }
            }
            let stop = await SSEClient.shared.onAgentTypingStop { eventChannelId, _ in
                guard eventChannelId == cid else { return }
                _Concurrency.Task { @MainActor in agentTypingName = nil }
            }
            unsubscribeTyping = [start, stop]
        }
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
            // Apple Intelligence parity with iOS: when the on-device model is the chosen agent,
            // Astrid answers locally. Mac never did this, so @Astrid did nothing here (8dded037).
            await OnDeviceAstrid.respondIfNeeded(channelId: cid, content: t,
                                                 listId: source.listIdForMembers)
        }
    }
}
#endif
