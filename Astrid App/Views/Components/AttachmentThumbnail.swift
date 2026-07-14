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
                    Text(NSLocalizedString("attachments.quick_look_tip", comment: "Tip about Markup in Quick Look"))
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

        print("✏️ [AttachmentThumbnail] Loading full image for editing: \(file.id)")

        // Check if we already have the full image from previous load
        if let fullImage = fullImage {
            onEdit?(file, fullImage)
            return
        }

        // Check if this is a local temp file (not yet uploaded)
        if file.id.hasPrefix("temp_") {
            if let localData = attachmentService.getLocalFileData(for: file.id) {
                // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
                let image = await MainActor.run { UIImage(data: localData) }
                if let image {
                    fullImage = image
                    onEdit?(file, image)
                }
            }
            return
        }

        // Check disk cache first
        if let cachedData = attachmentService.getCachedDownload(for: file.id) {
            // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
            let image = await MainActor.run { UIImage(data: cachedData) }
            if let image {
                fullImage = image
                onEdit?(file, image)
            }
            return
        }

        // Download from server
        do {
            let infoURL = "\(Constants.API.baseURL)/api/v1/secure-files/\(file.id)?info=true"
            guard let url = URL(string: infoURL) else { return }

            var request = URLRequest(url: url)
            if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            }

            let (infoData, infoResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = infoResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }

            struct FileInfo: Codable { let url: String }
            let fileInfo = try JSONDecoder().decode(FileInfo.self, from: infoData)
            guard let downloadURL = URL(string: fileInfo.url) else { return }

            let (fileData, _) = try await URLSession.shared.data(from: downloadURL)

            // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
            let image = await MainActor.run { UIImage(data: fileData) }
            if let image {
                // Cache for future use
                attachmentService.cacheDownload(fileId: file.id, data: fileData)
                fullImage = image
                onEdit?(file, image)
            }
        } catch {
            print("❌ [AttachmentThumbnail] Failed to load image for editing: \(error)")
        }
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

        // Check in-memory cache first
        if let cached = ThumbnailCache.shared.get(file.id) {
            thumbnailImage = cached
            return
        }

        // Check persistent disk cache (for offline viewing)
        if let cachedData = attachmentService.getCachedDownload(for: file.id) {
            print("✅ [AttachmentThumbnail] Found in disk cache: \(file.id)")

            if isImage {
                // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
                let image = await MainActor.run { UIImage(data: cachedData) }
                if let image {
                    thumbnailImage = image
                    ThumbnailCache.shared.set(image, for: file.id)
                    return
                }
            } else if isVideo || isPDF {
                // Generate thumbnail from cached data
                if let thumbnail = await generateThumbnail(from: cachedData, fileName: file.name) {
                    thumbnailImage = thumbnail
                    ThumbnailCache.shared.set(thumbnail, for: file.id)
                    return
                }
            }
        }

        isLoadingThumbnail = true

        print("🖼️ [AttachmentThumbnail] Loading thumbnail for: \(file.name) (id: \(file.id))")

        // Check if this is a local temp file (not yet uploaded)
        if file.id.hasPrefix("temp_") {
            print("🖼️ [AttachmentThumbnail] Loading from pending uploads cache...")
            if let localData = attachmentService.getLocalFileData(for: file.id) {
                if isImage {
                    // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
                    let image = await MainActor.run { UIImage(data: localData) }
                    if let image {
                        thumbnailImage = image
                        ThumbnailCache.shared.set(image, for: file.id)
                    }
                } else {
                    if let thumbnail = await generateThumbnail(from: localData, fileName: file.name) {
                        thumbnailImage = thumbnail
                        ThumbnailCache.shared.set(thumbnail, for: file.id)
                    }
                }
                isLoadingThumbnail = false
                return
            } else {
                print("❌ [AttachmentThumbnail] Failed to load from pending cache")
                isLoadingThumbnail = false
                return
            }
        }

        // Load from server for uploaded files
        do {
            // Get the signed download URL from the API
            let infoURL = "\(Constants.API.baseURL)/api/v1/secure-files/\(file.id)?info=true"
            guard let url = URL(string: infoURL) else {
                isLoadingThumbnail = false
                return
            }

            var request = URLRequest(url: url)
            if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            }

            let (infoData, infoResponse) = try await URLSession.shared.data(for: request)
            guard let httpResponse = infoResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                isLoadingThumbnail = false
                return
            }

            struct FileInfo: Codable { let url: String }
            let fileInfo = try JSONDecoder().decode(FileInfo.self, from: infoData)

            guard let downloadURL = URL(string: fileInfo.url) else {
                isLoadingThumbnail = false
                return
            }

            // For videos, we can try to get a thumbnail without downloading the whole file
            if isVideo {
                if let thumbnail = await generateVideoThumbnail(from: downloadURL) {
                    thumbnailImage = thumbnail
                    ThumbnailCache.shared.set(thumbnail, for: file.id)
                    isLoadingThumbnail = false
                    return
                }
            }

            // For images and PDFs, we need the data
            let (fileData, _) = try await URLSession.shared.data(from: downloadURL)

            if isImage {
                // UIImage(data:) must run on main thread to avoid "visual style disabled" warnings
                let image = await MainActor.run { UIImage(data: fileData) }
                if let image {
                    thumbnailImage = image
                    ThumbnailCache.shared.set(image, for: file.id)
                    attachmentService.cacheDownload(fileId: file.id, data: fileData)
                }
            } else if isPDF {
                if let thumbnail = await generateThumbnail(from: fileData, fileName: file.name) {
                    thumbnailImage = thumbnail
                    ThumbnailCache.shared.set(thumbnail, for: file.id)
                    attachmentService.cacheDownload(fileId: file.id, data: fileData)
                }
            } else if isVideo {
                // If remote thumbnail failed, try from downloaded data
                if let thumbnail = await generateThumbnail(from: fileData, fileName: file.name) {
                    thumbnailImage = thumbnail
                    ThumbnailCache.shared.set(thumbnail, for: file.id)
                    attachmentService.cacheDownload(fileId: file.id, data: fileData)
                }
            }

            isLoadingThumbnail = false

        } catch {
            print("❌ [AttachmentThumbnail] Failed to load thumbnail: \(error)")
            isLoadingThumbnail = false
        }
    }

    private func generateThumbnail(from data: Data, fileName: String) async -> UIImage? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + fileName)
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
            print("❌ [AttachmentThumbnail] Failed to generate video thumbnail: \(error)")
            return nil
        }
    }

    private func downloadAndPreview() async {
        isDownloading = true
        defer { isDownloading = false }

        print("📥 [AttachmentThumbnail] Opening file: \(file.name) (id: \(file.id))")

        // Check if this is a local temp file (not yet uploaded)
        if file.id.hasPrefix("temp_") {
            print("📥 [AttachmentThumbnail] Loading preview from pending uploads...")
            if let localData = attachmentService.getLocalFileData(for: file.id) {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent(file.name)

                do {
                    try localData.write(to: tempFileURL)
                    print("✅ [AttachmentThumbnail] Local file ready for preview")
                    quickLookURL = tempFileURL
                } catch {
                    print("❌ [AttachmentThumbnail] Failed to write temp file: \(error)")
                }
            } else {
                print("❌ [AttachmentThumbnail] Failed to load from pending cache")
            }
            return
        }

        // Check disk cache first (for offline viewing)
        if let cachedURL = attachmentService.getCachedFileURL(for: file.id, fileName: file.name) {
            print("✅ [AttachmentThumbnail] Opening from disk cache: \(file.id)")
            quickLookURL = cachedURL
            return
        }

        // Download from server for uploaded files
        do {
            // Get the signed download URL from the API
            let infoURL = "\(Constants.API.baseURL)/api/v1/secure-files/\(file.id)?info=true"
            guard let url = URL(string: infoURL) else {
                print("❌ [AttachmentThumbnail] Invalid URL")
                return
            }

            var request = URLRequest(url: url)

            // Add session cookie for authentication
            if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            }

            // Get the signed URL
            let (infoData, infoResponse) = try await URLSession.shared.data(for: request)

            guard let httpResponse = infoResponse as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("❌ [AttachmentThumbnail] Failed to get file info: \(infoResponse)")
                return
            }

            struct FileInfo: Codable {
                let url: String
                let fileName: String
                let mimeType: String
                let fileSize: Int
            }

            let decoder = JSONDecoder()
            let fileInfo = try decoder.decode(FileInfo.self, from: infoData)

            print("📥 [AttachmentThumbnail] Got signed URL, downloading...")

            // Download from the signed URL
            guard let downloadURL = URL(string: fileInfo.url) else {
                print("❌ [AttachmentThumbnail] Invalid download URL")
                return
            }

            let (fileData, _) = try await URLSession.shared.data(from: downloadURL)

            // Cache to disk for offline viewing
            attachmentService.cacheDownload(fileId: file.id, data: fileData)

            // Save to temporary directory with proper filename for QuickLook
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(file.name)

            try fileData.write(to: tempFileURL)

            print("✅ [AttachmentThumbnail] File downloaded and cached: \(tempFileURL.path)")

            // Show QuickLook preview
            quickLookURL = tempFileURL

        } catch {
            print("❌ [AttachmentThumbnail] Failed to download file: \(error)")
        }
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
