//  MacChatPanelView.swift
//  Astrid for Mac — per-list chat (E1). Resolve channel → messages → send, via ChatService.

#if os(macOS)
import SwiftUI

struct MacChatPanelView: View {
    let listId: String
    @StateObject private var chat = ChatService.shared
    @State private var channelId: String?
    @State private var messages: [ChatMessage] = []
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
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

    private func row(_ m: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(m.author?.displayName ?? "Someone").font(.caption).bold().foregroundStyle(Theme.textSecondary)
                if let d = m.createdAt { Text(d, style: .relative).font(.caption2).foregroundStyle(Theme.textMuted) }
            }
            Text(m.content).foregroundStyle(Theme.textPrimary)
                .padding(8).background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func load() async {
        channelId = try? await chat.resolveChannel(forListId: listId)
        await refresh()
    }

    private func refresh() async {
        guard let cid = channelId else { return }
        messages = (try? await chat.fetchMessages(channelId: cid)) ?? []
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let cid = channelId else { return }
        // Keep the draft until the send succeeds; surface failures instead of dropping the message.
        MacActions.perform("Send message") {
            _ = try await chat.sendMessage(channelId: cid, content: t)
            text = ""
            await refresh()
        }
    }
}
#endif
