import SwiftUI

/// Share a task or a list: generate a shortcode URL, copy it, or hand it to the iOS share sheet.
///
/// One view for both targets — `ShareTaskView` and `ShareListView` were the same 260 lines with
/// the word "task" swapped for "list" (2026-09-13 dedupe pass).
struct ShareTargetView: View {
    enum Target {
        case task(Task)
        case list(TaskList)
    }

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    let target: Target

    @State private var shareUrl: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCopiedConfirmation = false
    @State private var showShareSheet = false

    init(task: Task) { target = .task(task) }
    init(list: TaskList) { target = .list(list) }

    // MARK: - What differs between a task and a list

    private var targetType: String {
        switch target { case .task: return "task"; case .list: return "list" }
    }

    private var targetId: String {
        switch target { case .task(let t): return t.id; case .list(let l): return l.id }
    }

    private var name: String {
        switch target { case .task(let t): return t.title; case .list(let l): return l.name }
    }

    private var title: String {
        switch target {
        case .task: return NSLocalizedString("share.share_task", comment: "Share Task")
        case .list: return NSLocalizedString("share.share_list", comment: "Share List")
        }
    }

    private var linkHint: String {
        switch target {
        case .task: return NSLocalizedString("share.share_link_hint", comment: "Share this link with anyone who has access to view this task")
        case .list: return NSLocalizedString("share.share_list_link_hint", comment: "Share this link with anyone who has access to view this list")
        }
    }

    private var redirectHint: String {
        switch target {
        case .task: return NSLocalizedString("share.link_redirect_task", comment: "The link will redirect to the task in the app")
        case .list: return NSLocalizedString("share.link_redirect_list", comment: "The link will redirect to the list in the app")
        }
    }

    /// Icon, colour and text for the privacy banner, or nil when there is nothing to say.
    private var privacyNotice: (icon: String, color: Color, text: String)? {
        switch target {
        case .task(let task):
            guard task.isPrivate else { return nil }
            return ("lock.fill", Theme.accent,
                    NSLocalizedString("share.private_task_message", comment: "This is a private task. Only users with access to this list can view it."))
        case .list(let list):
            switch list.privacy {
            case .PRIVATE:
                return ("lock.fill", Theme.accent,
                        NSLocalizedString("share.private_list_message", comment: "This is a private list. Only members with access can view it."))
            case .PUBLIC:
                return ("globe", .green,
                        NSLocalizedString("share.public_list_message", comment: "This is a public list. Anyone with the link can view it."))
            default:
                return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing16) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.accent)
                    Text(title)
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }
                .padding(.top, Theme.spacing16)

                Text(name)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacing16)

                if let notice = privacyNotice {
                    HStack(alignment: .top, spacing: Theme.spacing8) {
                        Image(systemName: notice.icon)
                            .font(.system(size: 14))
                            .foregroundColor(notice.color)
                        Text(notice.text)
                            .font(Theme.Typography.caption1())
                            .foregroundColor(notice.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.spacing12)
                    .background(notice.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, Theme.spacing16)
                }

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

                        HStack(spacing: Theme.spacing12) {
                            Button {
                                copyToClipboard()
                            } label: {
                                HStack {
                                    Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                                    Text(showCopiedConfirmation
                                         ? NSLocalizedString("share.link_copied", comment: "Link copied!")
                                         : NSLocalizedString("actions.copy", comment: "Copy"))
                                }
                                .font(Theme.Typography.body())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.spacing12)
                                .background(showCopiedConfirmation ? Color.green : Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                            }
                            .buttonStyle(.plain)

                            Button {
                                showShareSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(NSLocalizedString("actions.share", comment: "Share"))
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

                        VStack(alignment: .leading, spacing: Theme.spacing4) {
                            HStack(alignment: .top, spacing: Theme.spacing8) {
                                Text("🔗")
                                Text(linkHint)
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(alignment: .top, spacing: Theme.spacing8) {
                                Text("📌")
                                Text(redirectHint)
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
                    Button(NSLocalizedString("actions.close", comment: "Close")) {
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
                targetType: targetType,
                targetId: targetId
            )
            shareUrl = response.url
            AppLog.debug("✅ [ShareTargetView] Generated share URL: \(response.url)")
        } catch {
            errorMessage = "Failed to generate share link. Please try again."
            AppLog.debug("❌ [ShareTargetView] Failed to generate share link: \(error)")
        }

        isLoading = false
    }

    private func copyToClipboard() {
        guard let shareUrl = shareUrl else { return }

        PlatformPasteboard.copy(shareUrl)
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
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ShareTargetView(
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
