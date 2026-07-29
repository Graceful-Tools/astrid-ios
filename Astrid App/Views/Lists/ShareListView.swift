import SwiftUI

/// Share List Modal
/// Generates a shareable shortcode URL and displays native iOS share sheet
struct ShareListView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    let list: TaskList

    @State private var shareUrl: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCopiedConfirmation = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing16) {
                // Header
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.accent)
                    Text(NSLocalizedString("share.share_list", comment: "Share List"))
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }
                .padding(.top, Theme.spacing16)

                // List name
                Text(list.name)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacing16)

                // Privacy notice (if list is private)
                if list.privacy == .PRIVATE {
                    HStack(alignment: .top, spacing: Theme.spacing8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.accent)

                        Text(NSLocalizedString("share.private_list_message", comment: "This is a private list. Only members with access can view it."))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.spacing12)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, Theme.spacing16)
                } else if list.privacy == .PUBLIC {
                    HStack(alignment: .top, spacing: Theme.spacing8) {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                            .foregroundColor(.green)

                        Text(NSLocalizedString("share.public_list_message", comment: "This is a public list. Anyone with the link can view it."))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.spacing12)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, Theme.spacing16)
                }

                // Loading / URL Display / Error
                if isLoading {
                    VStack(spacing: Theme.spacing12) {
                        ProgressView()
                        Text(NSLocalizedString("share.generating_link", comment: "Generating share link..."))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.spacing20)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, Theme.spacing16)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: Theme.spacing8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.spacing20)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, Theme.spacing16)
                } else if let shareUrl = shareUrl {
                    VStack(spacing: Theme.spacing12) {
                        // URL Display
                        HStack(spacing: Theme.spacing8) {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                            Text(shareUrl)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(Theme.spacing12)
                        .frame(maxWidth: .infinity)
                        .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

                        // Action Buttons
                        HStack(spacing: Theme.spacing12) {
                            // Copy Button
                            Button {
                                copyToClipboard()
                            } label: {
                                HStack {
                                    Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                                    Text(showCopiedConfirmation ? "Copied!" : "Copy")
                                }
                                .font(Theme.Typography.body())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.spacing12)
                                .background(showCopiedConfirmation ? Color.green : Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                            }
                            .buttonStyle(.plain)

                            // Share Button (Native iOS Share Sheet)
                            Button {
                                showShareSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.spacing12)
                                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                        .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Share info
                        VStack(alignment: .leading, spacing: Theme.spacing4) {
                            HStack(alignment: .top, spacing: Theme.spacing8) {
                                Text("🔗")
                                Text(NSLocalizedString("share.share_list_link_hint", comment: "Share this link with anyone who has access to view this list"))
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(alignment: .top, spacing: Theme.spacing8) {
                                Text("📌")
                                Text(NSLocalizedString("share.link_redirect_list", comment: "The link will redirect to the list in the app"))
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Theme.spacing16)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, Theme.spacing16)
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareUrl = shareUrl, let url = URL(string: shareUrl) {
                    ShareSheet(items: [url])
                }
            }
            .task {
                await generateShareLink()
            }
        }
    }

    // MARK: - Functions

    private func generateShareLink() async {
        guard shareUrl == nil && !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await RemoteResourceService.shared.createShortcode(
                targetType: "list",
                targetId: list.id
            )
            shareUrl = response.url
            print("✅ [ShareListView] Generated share URL: \(response.url)")
        } catch {
            errorMessage = "Failed to generate share link. Please try again."
            print("❌ [ShareListView] Failed to generate share link: \(error)")
        }

        isLoading = false
    }

    private func copyToClipboard() {
        guard let shareUrl = shareUrl else { return }

        UIPasteboard.general.string = shareUrl
        showCopiedConfirmation = true

        // Reset confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedConfirmation = false
        }
    }
}

// MARK: - Preview

#Preview {
    ShareListView(
        list: TaskList(
            id: "1",
            name: "Sample List with a Really Long Name That Should Truncate",
            color: "#3b82f6",
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .PRIVATE,
            publicListType: nil,
            ownerId: "user1",
            owner: nil,
            admins: nil,
            members: nil,
            listMembers: nil,
            invitations: nil,
            defaultAssigneeId: nil,
            defaultAssignee: nil,
            defaultPriority: nil,
            defaultRepeating: nil,
            defaultIsPrivate: nil,
            defaultDueDate: nil,
            defaultDueTime: nil,
            mcpEnabled: nil,
            mcpAccessLevel: nil,
            aiAstridEnabled: nil,
            preferredAiProvider: nil,
            fallbackAiProvider: nil,
            githubRepositoryId: nil,
            aiAgentsEnabled: nil,
            aiAgentConfiguredBy: nil,
            copyCount: nil,
            createdAt: Date(),
            updatedAt: Date(),
            description: "This is a sample list"
        )
    )
}
