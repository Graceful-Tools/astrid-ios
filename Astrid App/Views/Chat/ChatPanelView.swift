import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "ChatPanel")

/// Main chat panel for a list — resolves channel, displays messages, handles input
struct ChatPanelView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let listId: String
    var onSignedIn: (() -> Void)?  // Called after successful sign-in to redirect

    @StateObject private var chatService = ChatService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    @State private var channelId: String?
    @State private var isLoadingChannel = true
    @State private var channelError: String?
    @State private var messages: [ChatMessage] = []
    @State private var replyingTo: ChatMessage?
    @State private var availableAgents: [User] = []  // AI agents for @mention

    // Agent typing indicator
    @State private var agentTypingName: String?
    @State private var unsubscribeTypingStart: (@Sendable () -> Void)?
    @State private var unsubscribeTypingStop: (@Sendable () -> Void)?

    // SSE unsubscribe closures
    @State private var unsubscribeCreated: (@Sendable () -> Void)?
    @State private var unsubscribeUpdated: (@Sendable () -> Void)?
    @State private var unsubscribeDeleted: (@Sendable () -> Void)?

    // Polling fallback for when SSE is unreliable
    @State private var pollTimer: Timer?

    // Sign-in sheet for unauthenticated users
    @State private var showingSignInSheet = false

    /// Whether the user has a real server session (not just local offline mode)
    private var isSignedInToServer: Bool {
        (try? KeychainService.shared.getSessionCookie()) != nil
    }

    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoadingChannel {
                Spacer()
                ProgressView()
                    .tint(Theme.accent)
                Text("Loading chat...")
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .padding(.top, Theme.spacing8)
                Spacer()
            } else if !isSignedInToServer {
                // Not signed in — show sign-in prompt
                Spacer()
                VStack(spacing: Theme.spacing16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Text("List comments and agents require sign-in.")
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showingSignInSheet = true
                    } label: {
                        Text("Sign In Now")
                            .font(Theme.Typography.body())
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.spacing24)
                            .padding(.vertical, Theme.spacing12)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.spacing24)
                Spacer()
            } else if let error = channelError {
                Spacer()
                VStack(spacing: Theme.spacing12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.warning)
                    Text(error)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        _Concurrency.Task { await loadChannel() }
                    }
                    .font(Theme.Typography.body())
                    .foregroundColor(Theme.accent)
                }
                .padding(Theme.spacing24)
                Spacer()
            } else {
                // Offline indicator
                if !networkMonitor.isConnected {
                    HStack(spacing: Theme.spacing4) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12))
                        Text("Offline — messages will sync when connected")
                            .font(Theme.Typography.caption2())
                    }
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .padding(.horizontal, Theme.spacing12)
                    .padding(.vertical, Theme.spacing4)
                    .frame(maxWidth: .infinity)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                }

                // Messages
                if messages.isEmpty && !chatService.isLoading {
                    Spacer()
                    VStack(spacing: Theme.spacing8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted.opacity(0.5) : Theme.textMuted.opacity(0.5))
                        Text(NSLocalizedString("chat.empty", comment: "No messages yet"))
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        Text(NSLocalizedString("chat.empty.hint", comment: "Start a conversation or @mention an AI agent"))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted.opacity(0.7) : Theme.textMuted.opacity(0.7))
                    }
                    Spacer()
                } else {
                    ChatMessageListView(
                        messages: messages,
                        hasMore: chatService.hasMore[channelId ?? ""] ?? false,
                        isLoading: chatService.isLoading,
                        currentUserId: AuthManager.shared.userId,
                        onLoadMore: {
                            if let channelId = channelId {
                                try? await chatService.loadMoreMessages(channelId: channelId)
                            }
                        },
                        onReply: { message in
                            replyingTo = message
                        }
                    )
                }

                // Agent typing indicator
                if let typingName = agentTypingName {
                    AgentTypingIndicator(agentName: typingName)
                }

                // Floating input (matches QuickAddTaskView treatment)
                if let channelId = channelId {
                    ChatInputView(
                        channelId: channelId,
                        listId: listId,
                        availableAgents: availableAgents,
                        replyingTo: replyingTo,
                        onCancelReply: { replyingTo = nil }
                    )
                }
            }
        }
        .sheet(isPresented: $showingSignInSheet, onDismiss: {
            // After sign-in sheet closes, check if user is now authenticated
            if isSignedInToServer {
                onSignedIn?()
            }
        }) {
            NavigationStack {
                LoginView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkDidBecomeAvailable).merge(with:
                // Poll every second while sheet is open to detect sign-in
                Timer.publish(every: 1, on: .main, in: .common).autoconnect().map { _ in Notification(name: .networkDidBecomeAvailable) }
            )) { _ in
                if isSignedInToServer && showingSignInSheet {
                    showingSignInSheet = false
                }
            }
        }
        .task {
            await loadChannel()
        }
        .onDisappear {
            unsubscribeSSE()
            stopPolling()
        }
        .onChange(of: chatService.cachedMessages) { _, newValue in
            if let channelId = channelId {
                messages = newValue[channelId] ?? []
            }
        }
    }

    // MARK: - Channel Loading

    private func loadChannel() async {
        isLoadingChannel = true
        channelError = nil

        // Chat requires a real server session (not just local auth)
        let hasSession = (try? KeychainService.shared.getSessionCookie()) != nil
        guard hasSession else {
            isLoadingChannel = false
            // Will show sign-in prompt via the !isSignedInToServer check in body
            return
        }

        do {
            let resolvedChannelId: String
            if listId == "my-tasks" {
                // My Tasks uses a virtual channel scoped to the user
                let userId = AuthManager.shared.userId ?? "unknown"
                resolvedChannelId = try await chatService.resolveVirtualChannel(virtualKey: "virtual-chat:\(userId):my-tasks")
            } else {
                resolvedChannelId = try await chatService.resolveChannel(forListId: listId)
            }
            channelId = resolvedChannelId

            // Fetch messages
            let fetchedMessages = try await chatService.fetchMessages(channelId: resolvedChannelId)
            messages = fetchedMessages

            // Subscribe to SSE events + polling fallback
            subscribeToSSE(channelId: resolvedChannelId)
            startPolling(channelId: resolvedChannelId)

            // Fetch available agents for @mention (fire-and-forget)
            _Concurrency.Task {
                do {
                    let agentUsers = try await chatService.fetchAvailableAgentUsers()
                    await MainActor.run { self.availableAgents = agentUsers }
                } catch {
                    // Use cached agents if API fails
                    if let cached = AIAgentCache.shared.load() {
                        await MainActor.run { self.availableAgents = cached }
                    }
                }
            }
        } catch {
            logger.error("Failed to load chat channel for \(listId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if networkMonitor.isConnected {
                channelError = "Could not load chat: \(error.localizedDescription)"
            } else {
                // Offline: try to show cached messages if channel was previously resolved
                if let cachedChannelId = chatService.channelForList[listId] {
                    channelId = cachedChannelId
                    messages = chatService.cachedMessages[cachedChannelId] ?? []
                } else {
                    channelError = "Chat not available offline"
                }
            }
        }

        isLoadingChannel = false
    }

    // MARK: - SSE

    private func subscribeToSSE(channelId: String) {
        unsubscribeSSE()

        _Concurrency.Task {
            unsubscribeCreated = await SSEClient.shared.onChatMessageCreated { [channelId] message, eventChannelId in
                guard eventChannelId == channelId else { return }
                _Concurrency.Task { @MainActor in
                    ChatService.shared.handleMessageCreated(message, channelId: channelId)
                }
            }

            unsubscribeUpdated = await SSEClient.shared.onChatMessageUpdated { [channelId] message, eventChannelId in
                guard eventChannelId == channelId else { return }
                _Concurrency.Task { @MainActor in
                    ChatService.shared.handleMessageUpdated(message, channelId: channelId)
                }
            }

            unsubscribeDeleted = await SSEClient.shared.onChatMessageDeleted { [channelId] messageId, eventChannelId in
                guard eventChannelId == channelId else { return }
                _Concurrency.Task { @MainActor in
                    ChatService.shared.handleMessageDeleted(messageId, channelId: channelId)
                }
            }

            // Typing indicators
            unsubscribeTypingStart = await SSEClient.shared.onAgentTypingStart { [channelId] agentName, eventChannelId, _ in
                guard eventChannelId == channelId else { return }
                _Concurrency.Task { @MainActor in
                    self.agentTypingName = agentName
                }
            }

            unsubscribeTypingStop = await SSEClient.shared.onAgentTypingStop { [channelId] eventChannelId, _ in
                guard eventChannelId == channelId else { return }
                _Concurrency.Task { @MainActor in
                    self.agentTypingName = nil
                }
            }
        }
    }

    private func unsubscribeSSE() {
        unsubscribeCreated?()
        unsubscribeUpdated?()
        unsubscribeDeleted?()
        unsubscribeTypingStart?()
        unsubscribeTypingStop?()
        unsubscribeCreated = nil
        unsubscribeUpdated = nil
        unsubscribeDeleted = nil
        unsubscribeTypingStart = nil
        unsubscribeTypingStop = nil
    }

    // MARK: - Polling Fallback

    /// Start polling for new messages every 3 seconds as SSE backup
    private func startPolling(channelId: String) {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            _Concurrency.Task { @MainActor in
                guard AuthManager.shared.isAuthenticated else { return }
                guard let channelId = self.channelId else { return }
                do {
                    let merged = try await chatService.refreshMessagesFromServer(channelId: channelId)
                    self.messages = merged
                    if merged.last?.isFromAgent == true {
                        self.agentTypingName = nil
                    }
                } catch {
                    // Silent — polling failures are expected sometimes
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
