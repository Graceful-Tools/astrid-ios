import SwiftUI
import QuickLook

struct TaskAttachmentSectionView: View {
    let task: Task
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var commentService = CommentService.shared

    // Preview state - now tracks file IDs for save-to-Astrid support
    @State private var previewItems: [(fileId: String, url: URL)] = []
    @State private var selectedIndex: Int = 0
    @State private var isPreparingPreview = false
    @State private var showQuickLook = false

    /// The SHARED union (AITD-355), not a copy of it. This view used to spell the rule out
    /// itself, which is how the model's version came to be dead code while the copy here quietly
    /// dropped every legacy attachment's url.
    ///
    /// Comments come from `CommentService`'s cache rather than `task.comments`, because the cache
    /// is what this screen keeps current — that difference is exactly why the union takes them
    /// as a parameter.
    private var allFiles: [SecureFile] {
        task.allSecureFiles(comments: commentService.cachedComments[task.id])
    }

    var body: some View {
        let files = allFiles

        if !files.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(String(format: NSLocalizedString("attachments.count", comment: "Attachments count"), files.count))
                    .font(Theme.Typography.footnote())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .padding(.horizontal, Theme.spacing16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacing12) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            AttachmentThumbnail(
                                file: file,
                                colorScheme: colorScheme,
                                size: 64,
                                showDetails: false,
                                onTap: {
                                    prepareAndShowPreview(files: files, selectedFileId: file.id)
                                }
                                // No onEdit needed - QuickLook handles markup and saves to Astrid
                            )
                        }
                    }
                    .padding(.horizontal, Theme.spacing16)
                }

                Divider()
                    .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)
                    .padding(.top, Theme.spacing8)
            }
            .overlay {
                if isPreparingPreview {
                    ZStack {
                        Color.black.opacity(0.2)
                        ProgressView()
                            .tint(Theme.accent)
                    }
                    .edgesIgnoringSafeArea(.all)
                }
            }
            // Use UIKit-based QuickLook presentation for proper toolbar support
            .quickLookPresenter(items: previewItems, initialIndex: selectedIndex, isPresented: $showQuickLook)
        }
    }

    private func prepareAndShowPreview(files: [SecureFile], selectedFileId: String) {
        isPreparingPreview = true

        _Concurrency.Task {
            let results = await AttachmentService.shared.prepareFilesForPreview(files: files)
            await MainActor.run {
                // Store the full items with file IDs for save support
                self.previewItems = results

                // Find the index of the selected file in the successfully prepared URLs
                if let index = results.firstIndex(where: { $0.fileId == selectedFileId }) {
                    self.selectedIndex = index
                } else {
                    self.selectedIndex = 0
                }

                self.isPreparingPreview = false
                if !previewItems.isEmpty {
                    self.showQuickLook = true
                }
            }
        }
    }
}
