import SwiftUI

/// Scrollable list of chat messages with auto-scroll and pagination
struct ChatMessageListView: View {
    @Environment(\.colorScheme) var colorScheme
    let messages: [ChatMessage]
    let hasMore: Bool
    let isLoading: Bool
    let currentUserId: String?
    let onLoadMore: () async -> Void
    let onReply: (ChatMessage) -> Void

    @State private var scrollToBottom = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.spacing12) {
                    // Load more button at top
                    if hasMore {
                        Button {
                            _Concurrency.Task { await onLoadMore() }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(Theme.accent)
                                    .scaleEffect(0.8)
                            } else {
                                Text("Load earlier messages")
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing8)
                    }

                    // Date-grouped messages
                    ForEach(groupedMessages, id: \.date) { group in
                        // Date separator
                        Text(formatGroupDate(group.date))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing4)

                        ForEach(group.messages, id: \.stableId) { message in
                            ChatMessageBubble(
                                message: message,
                                isCurrentUser: message.authorId == currentUserId,
                                onReply: { onReply(message) }
                            )
                            .id(message.stableId)
                        }
                    }

                    // Invisible anchor for scrolling to bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, Theme.spacing12)
                .padding(.vertical, Theme.spacing8)
            }
            .withReferenceNavigation()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Date Grouping

    private struct MessageGroup {
        let date: Date
        let messages: [ChatMessage]
    }

    private var groupedMessages: [MessageGroup] {
        let calendar = Calendar.current
        var groups: [Date: [ChatMessage]] = [:]

        for message in messages {
            let date = message.createdAt ?? Date.distantPast
            let dayStart = calendar.startOfDay(for: date)
            if groups[dayStart] == nil {
                groups[dayStart] = []
            }
            groups[dayStart]?.append(message)
        }

        return groups.keys.sorted().map { date in
            MessageGroup(date: date, messages: groups[date] ?? [])
        }
    }

    private func formatGroupDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}
