import SwiftUI
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "ChatMessageBubble")

/// Individual chat message bubble with agent indicator support
struct ChatMessageBubble: View {
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    @Environment(\.colorScheme) var colorScheme
    let message: ChatMessage
    let isCurrentUser: Bool
    let onReply: () -> Void

    @State private var showingDeleteAlert = false

    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    private var hasTextContent: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentUserBubbleBackground: Color {
        if effectiveTheme == "ocean" {
            return Color.white
        } else if effectiveTheme == "dark" {
            return Theme.Dark.bgSecondary
        } else {
            return Theme.bgSecondary
        }
    }

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

    private var agentBubbleBackground: Color {
        if effectiveTheme == "ocean" {
            return Color(red: 237/255, green: 233/255, blue: 254/255)  // Light purple
        } else if effectiveTheme == "dark" {
            return Color(red: 55/255, green: 48/255, blue: 83/255)    // Dark purple
        } else {
            return Color(red: 243/255, green: 240/255, blue: 255/255) // Very light purple
        }
    }

    private var contextMenu: some View {
        Group {
            Button {
                UIPasteboard.general.string = message.content
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
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Theme.spacing4) {
            HStack(alignment: .center, spacing: Theme.spacing8) {
                // Left avatar (other users / agents)
                if !isCurrentUser {
                    avatarView
                } else {
                    Spacer(minLength: 48)
                }

                // Message bubble
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    // Attachments
                    if let secureFiles = message.secureFiles, !secureFiles.isEmpty {
                        ChatAttachmentView(
                            files: secureFiles,
                            allTaskFiles: secureFiles,
                            colorScheme: colorScheme,
                            contextMenuContent: { contextMenu }
                        )
                    }

                    // Content — with colored @mentions, #lists, !tasks
                    if hasTextContent {
                        Text(message.content.attributedWithReferences(
                            defaultColor: colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary
                        ))
                        .font(Theme.Typography.body())
                    }
                }
                .padding(Theme.spacing12)
                .background(
                    Group {
                        if message.isFromAgent {
                            agentBubbleBackground
                        } else if isCurrentUser {
                            currentUserBubbleBackground
                        } else {
                            otherUserBubbleBackground
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .opacity(message.isPending ? 0.6 : 1.0)
                .contentShape(Rectangle())
                .contextMenu { contextMenu }

                // Right avatar (current user)
                if isCurrentUser {
                    avatarView
                } else {
                    Spacer(minLength: 48)
                }
            }

            // Name, agent badge, and timestamp
            HStack(spacing: Theme.spacing4) {
                if isCurrentUser {
                    Spacer()
                } else {
                    Spacer().frame(width: 40)
                }

                if message.isFromAgent {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)
                }

                Text(isCurrentUser ? NSLocalizedString("assignee.you", comment: "You") : (message.author?.displayName ?? "Unknown"))
                    .font(Theme.Typography.caption2())
                    .fontWeight(.medium)
                    .foregroundColor(message.isFromAgent ? .purple : (colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted))

                if let createdAt = message.createdAt {
                    Text("·")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Text(formatMessageDate(createdAt))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }

                if message.isPending {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }

                if isCurrentUser {
                    Spacer().frame(width: 40)
                } else {
                    Spacer()
                }
            }
        }
        .alert(NSLocalizedString("actions.delete", comment: "Delete"), isPresented: $showingDeleteAlert) {
            Button(NSLocalizedString("actions.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("actions.delete", comment: "Delete"), role: .destructive) {
                _Concurrency.Task {
                    try? await ChatService.shared.deleteMessage(id: message.id, channelId: message.channelId)
                }
            }
        } message: {
            Text("Are you sure you want to delete this message?")
        }
    }

    /// Resolve image URL — handles relative paths and picks best size for avatar
    private var resolvedImageURL: URL? {
        guard let image = message.author?.image, !image.isEmpty else { return nil }
        if image.hasPrefix("http") {
            return URL(string: image)
        }
        // Relative path — resolve against API base URL
        let baseURL = Constants.API.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Use 128x128 for crisp rendering on @2x/@3x displays (32pt avatar)
        var path = image
        if path.contains("icon-96x96") {
            path = path.replacingOccurrences(of: "icon-96x96", with: "icon-128x128")
        }
        return URL(string: baseURL + path)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = resolvedImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                case .failure, .empty:
                    initialsAvatar
                @unknown default:
                    initialsAvatar
                }
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        ZStack {
            if let brandAsset = message.author?.agentBrandImageAsset {
                Image(brandAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(message.isFromAgent ? Color.purple.opacity(0.2) : Theme.accent.opacity(0.2))
                    .frame(width: 32, height: 32)

                if message.isFromAgent {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                } else {
                    Text(message.author?.initials ?? "?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func formatMessageDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        }
        return formatter.string(from: date)
    }
}
