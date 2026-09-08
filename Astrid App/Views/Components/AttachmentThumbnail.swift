import SwiftUI
import QuickLook
import QuickLookThumbnailing
import AVFoundation
import Combine

/// Shared cache for thumbnail images to prevent reloading when views recreate
@MainActor

/// Displays a thumbnail for an attachment/secure file (matches web mobile styling)
struct AttachmentThumbnail: View {
    let file: SecureFile
    let colorScheme: ColorScheme
    var size: CGFloat = 64
    var contentMode: ContentMode = .fill
    var showDetails: Bool = false
    var onTap: (() -> Void)? = nil
    var onEdit: ((SecureFile, UIImage) -> Void)? = nil  // Called when user wants to edit an image

    @StateObject private var attachmentService = AttachmentService.shared
    @State private var isDownloading = false
    @State private var quickLookURL: URL?
    @State private var showingQuickLook = false
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = false
    @State private var fullImage: UIImage?  // For editing - full resolution image

    private var thumbnailContent: some View {
        ZStack {
            // Background for all file types
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                )

            // Content: either thumbnail image or file icon
            if let thumbnailImage = thumbnailImage {
                // Show actual image thumbnail
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipped() // Ensure image doesn't overflow
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                // Video play icon overlay
                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 2)
                }
            } else if isLoadingThumbnail {
                // Loading state
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(0.8)
            } else {
                // File icon for documents
                VStack(spacing: 4) {
                    Image(systemName: fileIcon)
                        .font(.system(size: size * 0.4))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                    if showDetails {
                        Text(file.name)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
            }

            // Download indicator overlay when tapped
            if isDownloading {
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(Color.black.opacity(0.5))
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            }
        }
        // CRITICAL: Fixed frame to prevent thumbnail from expanding on iPad
        .frame(width: size, height: size)
        .clipped()
    }

    var body: some View {
        thumbnailContent
            .contentShape(Rectangle())
            .onTapGesture {
                if let onTap = onTap {
                    onTap()
                } else {
                    _Concurrency.Task {
                        await downloadAndPreview()
                    }
                }
            }
            .contextMenu {
                Button {
                    if let onTap = onTap {
                        onTap()
                    } else {
                        _Concurrency.Task {
                            await downloadAndPreview()
                        }
                    }
                } label: {
                    Label(NSLocalizedString("attachments.quick_look", comment: "Quick Look"), systemImage: "eye")
                }

                // Hint about markup functionality
                if isImage {
                    Text(Brand.localized("attachments.quick_look_tip"))
                        .font(.caption)
                }
            }
            // Only use built-in quickLookPreview when parent doesn't handle preview (onTap is nil)
            .quickLookPreview(onTap == nil ? $quickLookURL : .constant(nil))
        .onReceive(NotificationCenter.default.publisher(for: .attachmentUpdated)) { notification in
            // Refresh thumbnail when this file is updated (e.g., after QuickLook markup edit)
            if let updatedFileId = notification.userInfo?["fileId"] as? String,
               updatedFileId == file.id,
               let cached = ThumbnailCache.shared.get(file.id) {
                thumbnailImage = cached
            }
        }
        .task(id: file.id) {
            // Only load if we don't already have a thumbnail
            if (isImage || isVideo || isPDF) && thumbnailImage == nil {
                // Check cache first (prevents reload when view recreates)
                if let cached = ThumbnailCache.shared.get(file.id) {
                    thumbnailImage = cached
                } else {
                    await loadThumbnail()
                }
            }
        }
        .onAppear {
            // Restore thumbnail from cache immediately on appear (before task runs)
            if (isImage || isVideo || isPDF) && thumbnailImage == nil {
                if let cached = ThumbnailCache.shared.get(file.id) {
                    thumbnailImage = cached
                }
            }
        }
    }

    // MARK: - Load Full Image for Editing

    private func loadFullImageAndEdit() async {
        guard isImage else { return }

        isDownloading = true
        defer { isDownloading = false }

        AppLog.debug("✏️ [AttachmentThumbnail] Loading full image for editing: \(file.id)")

        // Check if we already have the full image from previous load
        if let fullImage = fullImage {
            onEdit?(file, fullImage)
            return
        }

        // The bytes, wherever they already are: staged local copy, disk cache, then the server.
        // That ladder is `AttachmentService.fileData(for:)` — this view used to spell it out for
        // itself, over `URLSession.shared`, which skipped the app timeout, the path-safety
        // backstop and UI-test cookie isolation (AITD-353).
        guard let data = await attachmentService.fileData(for: file.id) else {
            AppLog.debug("❌ [AttachmentThumbnail] No data for editing: \(file.id)")
            return
        }

        // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
        guard let image = await MainActor.run(body: { UIImage(data: data) }) else { return }
        fullImage = image
        onEdit?(file, image)
    }

    // MARK: - Image Properties

    private var isImage: Bool {
        file.mimeType.lowercased().hasPrefix("image/")
    }
    
    private var isVideo: Bool {
        file.mimeType.lowercased().hasPrefix("video/")
    }
    
    private var isPDF: Bool {
        file.mimeType.lowercased().contains("pdf")
    }

    // MARK: - Download & Preview

    private func loadThumbnail() async {
        guard isImage || isVideo || isPDF else { return }

        // In-memory first — this one is per-thumbnail and not the service's business.
        if let cached = ThumbnailCache.shared.get(file.id) {
            thumbnailImage = cached
            return
        }

        isLoadingThumbnail = true
        defer { isLoadingThumbnail = false }

        AppLog.debug("🖼️ [AttachmentThumbnail] Loading thumbnail for: \(file.name) (id: \(file.id))")

        // A video can give up a poster frame from its signed URL without downloading the file at
        // all, so it is worth asking for the URL before asking for the bytes. This is the one
        // reason the view still needs `getSecureFileDownloadURL` rather than only `fileData`.
        if isVideo, !file.id.hasPrefix("temp_"),
           let downloadURL = try? await attachmentService.getSecureFileDownloadURL(for: file.id),
           let thumbnail = await generateVideoThumbnail(from: downloadURL) {
            thumbnailImage = thumbnail
            ThumbnailCache.shared.set(thumbnail, for: file.id)
            return
        }

        // Otherwise the bytes, from wherever they already are (AITD-353): the service walks the
        // staged copy → disk cache → server ladder this view used to re-implement, and caches
        // what it downloads, so the `cacheDownload` calls that used to live here are gone too.
        guard let data = await attachmentService.fileData(for: file.id) else {
            AppLog.debug("❌ [AttachmentThumbnail] No data for thumbnail: \(file.id)")
            return
        }

        if isImage {
            // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
            if let image = await MainActor.run(body: { UIImage(data: data) }) {
                thumbnailImage = image
                ThumbnailCache.shared.set(image, for: file.id)
            }
        } else if let thumbnail = await generateThumbnail(from: data, fileName: file.name) {
            thumbnailImage = thumbnail
            ThumbnailCache.shared.set(thumbnail, for: file.id)
        }
    }

    private func generateThumbnail(from data: Data, fileName: String) async -> UIImage? {
        // AITD-312: the UUID prefix does not stop "../" — the name still has to be sanitised.
        let tempURL = AttachmentFileName.temporaryURL(
            in: FileManager.default.temporaryDirectory,
            for: UUID().uuidString + "_" + AttachmentFileName.sanitized(fileName)
        )
        try? data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let request = QLThumbnailGenerator.Request(fileAt: tempURL, size: CGSize(width: size * 2, height: size * 2), scale: UIScreen.main.scale, representationTypes: .all)
        
        return await withCheckedContinuation { continuation in
            // Use generateBestRepresentation which calls the handler exactly once
            // (generateRepresentations calls multiple times causing continuation crash)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                continuation.resume(returning: representation?.uiImage)
            }
        }
    }
    
    private func generateVideoThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            AppLog.debug("❌ [AttachmentThumbnail] Failed to generate video thumbnail: \(error)")
            return nil
        }
    }

    private func downloadAndPreview() async {
        isDownloading = true
        defer { isDownloading = false }

        AppLog.debug("📥 [AttachmentThumbnail] Opening file: \(file.name) (id: \(file.id))")

        // The SAME preparer the Mac's comment attachments use — staged local copy, disk cache,
        // then the server, ending in a file Quick Look can open (AITD-353). Beyond dropping the
        // duplicated ladder, this inherits AITD-344's per-file preview directories: the temp path
        // this view used to build was keyed on the file NAME, so two attachments both called
        // "photo.png" resolved to one path and overwrote each other.
        let prepared = await attachmentService.prepareFilesForPreview(files: [file])
        guard let first = prepared.first else {
            AppLog.debug("❌ [AttachmentThumbnail] Could not prepare \(file.id) for preview")
            return
        }
        quickLookURL = first.url
    }
    private var fileIcon: String {
        let mimeType = file.mimeType.lowercased()

        if mimeType.hasPrefix("image/") {
            return "photo"
        } else if mimeType.hasPrefix("video/") {
            return "video"
        } else if mimeType.hasPrefix("audio/") {
            return "waveform"
        } else if mimeType.contains("pdf") {
            return "doc.text"
        } else if mimeType.contains("zip") || mimeType.contains("archive") {
            return "archivebox"
        } else {
            return "doc"
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        AttachmentThumbnail(
            file: SecureFile(
                id: "1",
                name: "screenshot.png",
                size: 1024 * 512, // 512 KB
                mimeType: "image/png"
            ),
            colorScheme: .light
        )

        AttachmentThumbnail(
            file: SecureFile(
                id: "2",
                name: "document.pdf",
                size: 1024 * 1024 * 2, // 2 MB
                mimeType: "application/pdf"
            ),
            colorScheme: .light
        )
    }
    .padding()
    .background(Theme.bgPrimary)
}
