//  MacCommentAttachments.swift
//  Astrid for Mac — a comment's own files, drawn in the comment (Task AITD-304).
//
//  Attachments reach a task THROUGH comments: the paperclip stages a file, the shared
//  CommentAttachmentBatch turns it into one comment per file, and the Outbox upload→comment
//  chain lands it. All of that worked. What did not exist was any way to SEE the result — the
//  Mac comment bubble drew `Text(comment.content)` and nothing else, so a file posted without a
//  caption rendered as an empty pill. "Not attaching" and "attached, never drawn" look identical
//  from the outside, which is why this was reported as a broken upload.
//
//  The task-level Attachments section is no help either: it lists task.attachments and
//  task.secureFiles, and a file that came in on a comment is on the COMMENT.

#if os(macOS)
import SwiftUI
import AppKit

/// Pure rules for what a comment bubble draws. Kept out of the view so the empty-bubble decision
/// — the actual bug — is testable without rendering anything.
enum MacCommentBubble {
    /// The files this comment carries.
    static func attachments(of comment: Comment) -> [SecureFile] { comment.secureFiles ?? [] }

    /// A caption-less attachment comment gets NO text bubble. An empty pill beside a photo reads
    /// as a failed post, and an empty pill on its own is exactly what this bug looked like.
    static func showsText(_ content: String) -> Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Nothing to draw at all — neither text nor a file.
    static func isEmpty(_ comment: Comment) -> Bool {
        !showsText(comment.content) && attachments(of: comment).isEmpty
    }

    /// Images are shown; everything else (documents, video, audio) is a chip that opens in Quick
    /// Look. NSImage would happily return nil for a .mov's bytes, so guessing wider would only
    /// trade a chip for a grey box.
    static func rendersInline(mimeType: String) -> Bool {
        mimeType.lowercased().hasPrefix("image/")
    }
}

/// The files on one comment, stacked above its text.
struct MacCommentAttachmentsView: View {
    let files: [SecureFile]
    /// Opening is the host's job — the detail panel already owns a Quick Look presenter.
    let onOpen: (SecureFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(files, id: \.id) { file in
                MacCommentAttachmentItem(file: file, onOpen: onOpen)
            }
        }
    }
}

/// One attachment: an image thumbnail, or an icon + name + size chip.
struct MacCommentAttachmentItem: View {
    let file: SecureFile
    let onOpen: (SecureFile) -> Void

    @State private var image: NSImage?
    @State private var loading = false

    /// Wide enough to read a screenshot at a glance, narrow enough to sit in a chat bubble.
    private static let maxWidth: CGFloat = 240
    private static let maxHeight: CGFloat = 300

    private var isImage: Bool { MacCommentBubble.rendersInline(mimeType: file.mimeType) }

    var body: some View {
        Group {
            if isImage {
                imageBody
            } else {
                documentChip
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(file) }
        .macPointingHand()
        .help(file.name)
        .accessibilityLabel(file.name)
        .task(id: file.id) {
            guard isImage, image == nil else { return }
            await loadImage()
        }
    }

    @ViewBuilder private var imageBody: some View {
        if let image {
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fit)
                .frame(maxWidth: Self.maxWidth, maxHeight: Self.maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            // A placeholder the size of a small thumbnail, so the bubble does not jump when the
            // bytes arrive — and never nothing, which is the state this whole task is about.
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.bgTertiary)
                .frame(width: 120, height: 90)
                .overlay {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "photo").foregroundStyle(Theme.textMuted)
                    }
                }
        }
    }

    private var documentChip: some View {
        HStack(spacing: 8) {
            Image(systemName: MacAttachmentIcon.symbol(type: file.mimeType, name: file.name))
                .font(.system(size: 20)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.caption).lineLimit(1).foregroundStyle(Theme.textPrimary)
                let size = MacAttachmentIcon.humanSize(file.size)
                if !size.isEmpty {
                    Text(size).font(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(8)
        .background(Theme.bgTertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Thumbnail cache first (shared with iOS, and aliased temp→real when an upload completes),
    /// then the SHARED byte ladder in AttachmentService. No Mac-local copy of that ladder.
    private func loadImage() async {
        if let cached = ThumbnailCache.shared.get(file.id) {
            image = cached
            return
        }
        loading = true
        defer { loading = false }
        guard let data = await AttachmentService.shared.fileData(for: file.id),
              let loaded = NSImage(data: data) else { return }
        ThumbnailCache.shared.set(loaded, for: file.id)
        image = loaded
    }
}
#endif
