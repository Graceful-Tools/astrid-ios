import SwiftUI

/// Share Task Modal
/// Generates a shareable shortcode URL and displays native iOS share sheet
struct ShareTaskView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    let task: Task

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
                    Text(NSLocalizedString("share.share_task", comment: "Share Task"))
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }
                .padding(.top, Theme.spacing16)

                // Task title
                Text(task.title)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacing16)

                // Privacy notice (if task is private)
                if task.isPrivate {
                    HStack(alignment: .top, spacing: Theme.spacing8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)

                        Text(NSLocalizedString("share.private_task_message", comment: "This is a private task. Only users with access to this list can view it."))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.blue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.spacing12)
                    .background(Color.blue.opacity(0.1))
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
                                Text(NSLocalizedString("share.share_link_hint", comment: "Share this link with anyone who has access to view this task"))
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(alignment: .top, spacing: Theme.spacing8) {
                                Text("📌")
                                Text(NSLocalizedString("share.link_redirect_task", comment: "The link will redirect to the task in the app"))
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
                targetType: "task",
                targetId: task.id
            )
            shareUrl = response.url
            print("✅ [ShareTaskView] Generated share URL: \(response.url)")
        } catch {
            errorMessage = "Failed to generate share link. Please try again."
            print("❌ [ShareTaskView] Failed to generate share link: \(error)")
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

// MARK: - Native Share Sheet Wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Preview

#Preview {
    ShareTaskView(
        task: Task(
            id: "1",
            title: "Sample Task with a Really Long Title That Should Truncate",
            description: "This is a sample task",
            creatorId: "user1",
            isAllDay: false,
            repeating: .never,
            priority: .high,
            isPrivate: false,
            completed: false
        )
    )
}
