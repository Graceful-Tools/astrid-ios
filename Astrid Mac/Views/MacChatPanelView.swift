//  MacChatPanelView.swift
//  Astrid for Mac — per-list chat (E1, made real-time/paginated/offline-aware in Task 91f2626d).
//  Binds to ChatService.cachedMessages (updated live by SSE handlers), paginates history, and
//  shows pending/failed sends. Send stays offline-first via the shared service.

#if os(macOS)
import SwiftUI

struct MacChatPanelView: View {
    let listId: String
    @StateObject private var chat = ChatService.shared
    @State private var channelId: String?
    @State private var text = ""
    @State private var loadingMore = false

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
            HStack {
                TextField("Message…", text: $text).textFieldStyle(.roundedBorder).onSubmit(send)
                Button("Send", action: send).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .task(id: listId) { await load() }
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
    }

    private func load() async {
        channelId = try? await chat.resolveChannel(forListId: listId)
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
        MacActions.perform("Send message") {
            _ = try await chat.sendMessage(channelId: cid, content: t)
            text = ""
        }
    }
}
#endif
