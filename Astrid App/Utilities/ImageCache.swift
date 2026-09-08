import Foundation
import SwiftUI
import Combine

/// Coalesces simultaneous work for the same URL. A list can render the same person dozens of
/// times before the first network response returns; URL-keyed in-flight work ensures those rows
/// await one fetch instead of each starting their own (AITD-283).
@MainActor
final class URLLoadCoordinator<Value> {
    private var inFlight: [URL: _Concurrency.Task<Value?, Never>] = [:]

    /// Outstanding loads are pointless once nobody is left to receive them, so cancel them.
    ///
    /// This deinit is also load-bearing for the BUILD: with the synthesized one, Swift 6.3.3
    /// crashes in the optimizer (`EarlyPerfInliner` on `URLLoadCoordinator.deinit`) whenever this
    /// file is compiled with `-O`, which is every Release archive. Giving the deinit a body avoids
    /// the crashing path. Verified 2026-08-23 against `swiftc -O` for both the macOS and iOS
    /// targets; if that compiler bug is ever fixed, this is still correct code to keep.
    deinit {
        for task in inFlight.values { task.cancel() }
    }

    func load(for url: URL, operation: @escaping @MainActor () async -> Value?) async -> Value? {
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = _Concurrency.Task { @MainActor in
            await operation()
        }
        inFlight[url] = task
        let value = await task.value
        inFlight.removeValue(forKey: url)
        return value
    }
}

/// In-memory and disk image cache for fast loading
class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSURL, PlatformImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    /// How much disk the image cache may occupy (AITD-345). The memory cache has always been
    /// bounded; the disk one only ever shrank on sign-out.
    static let diskByteLimit = 100 * 1024 * 1024

    private init() {
        // Setup memory cache limits
        memoryCache.countLimit = 100 // Max 100 images in memory
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB memory limit

        // Setup disk cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("ListImageCache", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        AppLog.debug("📦 [ImageCache] Initialized with cache directory: \(cacheDirectory.path)")

        // A cache that grew before the limit existed is the case to fix, so sweep at launch.
        enforceDiskLimit()
    }

    /// Memory only — no disk, no decode, safe to call during a SwiftUI body evaluation.
    ///
    /// The fast path `CachedImageLoader` uses. It used to call `get(url:)`, which reads and
    /// decodes from disk synchronously, so every memory miss did file I/O and an image decode
    /// inside a render pass (AITD-345).
    func memoryImage(for url: URL) -> PlatformImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    /// Drop least-recently-used images until the disk cache is inside its budget.
    ///
    /// Same policy as the attachment cache — `FileCacheEviction`, written once and shared
    /// (AITD-344 built it for exactly this).
    func enforceDiskLimit(cap: Int = ImageCache.diskByteLimit) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: keys
        ) else { return }

        let entries: [FileCacheEntry] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { return nil }
            let accessed = values.contentAccessDate ?? values.contentModificationDate ?? Date()
            return FileCacheEntry(id: url.lastPathComponent, size: size, lastAccess: accessed)
        }

        let doomed = FileCacheEviction.idsToEvict(entries, cap: cap)
        guard !doomed.isEmpty else { return }
        for id in doomed {
            try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent(id))
        }
        AppLog.debug("🧹 [ImageCache] Evicted \(doomed.count) images over the \(cap) byte cap")
    }

    /// Memory, then a SYNCHRONOUS disk read and decode.
    ///
    /// Deliberately kept for `UserImageCache.prepareForLaunch`, which warms exactly one avatar
    /// before the first My Tasks frame so the row does not visibly flip from initials to a photo
    /// (AITD-283). That is a considered trade of a single blocking read for a visual glitch.
    ///
    /// It is NOT the general path — `CachedImageLoader` uses `memoryImage(for:)` and then the
    /// async disk read, because doing this per image inside a render is what AITD-345 was about.
    /// `ImageCacheLoadPathTests` keeps it that way.
    /// WARNING: Only call from main thread to avoid "visual style disabled" warnings
    func get(url: URL) -> PlatformImage? {
        // Check memory cache first
        if let cached = memoryCache.object(forKey: url as NSURL) {
            AppLog.debug("✅ [ImageCache] Memory hit: \(url.lastPathComponent)")
            return cached
        }

        // Check disk cache
        let fileURL = diskCacheURL(for: url)
        if let data = try? Data(contentsOf: fileURL),
           let image = PlatformImage(data: data) {
            // Store in memory cache for next time
            memoryCache.setObject(image, forKey: url as NSURL)
            AppLog.debug("💾 [ImageCache] Disk hit: \(url.lastPathComponent)")
            return image
        }

        return nil
    }

    /// Get image from cache asynchronously - safe to call from background
    /// Returns nil if not in cache, otherwise loads from disk on background and creates PlatformImage on main thread
    func getAsync(url: URL) async -> PlatformImage? {
        // Check memory cache first (thread-safe)
        if let cached = memoryCache.object(forKey: url as NSURL) {
            AppLog.debug("✅ [ImageCache] Memory hit: \(url.lastPathComponent)")
            return cached
        }

        // Read data from disk on current thread (background-safe)
        let fileURL = diskCacheURL(for: url)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        // Create PlatformImage on main thread to avoid "visual style disabled" warning
        return await MainActor.run {
            guard let image = PlatformImage(data: data) else { return nil as PlatformImage? }
            memoryCache.setObject(image, forKey: url as NSURL)
            AppLog.debug("💾 [ImageCache] Disk hit: \(url.lastPathComponent)")
            return image
        }
    }

    /// Store an image and the bytes it was decoded from.
    ///
    /// The BYTES are what goes to disk (AITD-345). This used to write `image.pngDataCompat()` —
    /// a lossless PNG re-encode of whatever came down, so a 200 KB JPEG avatar became a
    /// multi-megabyte PNG, and the encode ran on the main actor. The original response bytes are
    /// both smaller and free, and they are already in hand at the one call site.
    func store(_ data: Data, image: PlatformImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
        try? data.write(to: diskCacheURL(for: url))
        AppLog.debug("💾 [ImageCache] Cached: \(url.lastPathComponent) (\(data.count / 1024) KB)")
        enforceDiskLimit()
    }



    /// Clear all caches
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        AppLog.debug("🗑️ [ImageCache] Cache cleared")
    }

    /// Clear memory cache only (keeps disk cache for offline)
    /// Call this when app becomes active to refresh images from server
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        AppLog.debug("🗑️ [ImageCache] Memory cache cleared")
    }

    /// Remove a specific URL from cache
    func remove(url: URL) {
        memoryCache.removeObject(forKey: url as NSURL)
        let fileURL = diskCacheURL(for: url)
        try? fileManager.removeItem(at: fileURL)
        AppLog.debug("🗑️ [ImageCache] Removed: \(url.lastPathComponent)")
    }

    /// Clear all secure-files entries (user uploads that may have changed)
    func clearSecureFilesCache() {
        // Clear from memory - need to enumerate
        // Since NSCache doesn't support enumeration, clear all memory
        memoryCache.removeAllObjects()

        // Clear secure-files from disk
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                if file.lastPathComponent.contains("api_secure-files") {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
        AppLog.debug("🗑️ [ImageCache] Secure files cache cleared")
    }

    /// Get disk cache URL for a remote URL
    private func diskCacheURL(for url: URL) -> URL {
        let filename = url.absoluteString
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent(filename)
    }
}

/// Async image loader with caching
@MainActor
class CachedImageLoader: ObservableObject {
    private static let loadCoordinator = URLLoadCoordinator<PlatformImage>()

    @Published var image: PlatformImage?
    @Published var isLoading = false

    /// NOT a `let`. A `@StateObject` lives as long as the view's identity, so a loader that owned
    /// its URL forever would ignore every later change — the list image you just picked, the avatar
    /// after a profile photo change, an assignee swapped on a row (Task 16f39f36).
    private var url: URL
    private var loadTask: _Concurrency.Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    /// Point the loader at `url` and fetch it.
    ///
    /// Re-pointing drops the previous picture rather than leaving it up: the old list's image under
    /// the new list's name is a worse answer than the placeholder for a moment.
    func load(url newURL: URL) {
        guard newURL != url else {
            if image == nil { load() }   // idempotent — a redraw must not blank what we already have
            return
        }
        loadTask?.cancel()
        url = newURL
        image = nil
        load()
    }

    /// No URL to show (the model's image was removed) — stop and fall back to the placeholder.
    func clear() {
        loadTask?.cancel()
        image = nil
        isLoading = false
    }

    func load() {
        // MEMORY only. Reading and decoding from disk here meant file I/O inside a SwiftUI
        // render on every memory miss; the disk check moved into the async task below (AITD-345).
        if let cached = ImageCache.shared.memoryImage(for: url) {
            self.image = cached
            return
        }

        // Load from network
        let requested = url          // a slow response for a URL we have since left must not land
        isLoading = true
        loadTask = _Concurrency.Task {
            // First check disk cache asynchronously (safe from background)
            if let cached = await ImageCache.shared.getAsync(url: requested) {
                guard !_Concurrency.Task.isCancelled, requested == self.url else { return }
                self.image = cached
                isLoading = false
                return
            }

            let loadedImage = await Self.loadCoordinator.load(for: requested) {
                do {
                    let data: Data

                    // Check if this is a secure-files URL that requires authentication.
                    // Match both /api/secure-files/ (older stored URLs) and /api/v1/secure-files/
                    // (new emissions) so cached attachments from before the v1 cutover keep loading.
                    if requested.path.contains("/api/secure-files/") || requested.path.contains("/api/v1/secure-files/") {
                        var request = URLRequest(url: requested)
                        // Add session cookie for authentication
                        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                        }
                        let (responseData, _) = try await AstridHTTP.session.data(for: request)
                        data = responseData
                    } else {
                        // Public URL, no auth needed
                        let (responseData, _) = try await AstridHTTP.session.data(from: requested)
                        data = responseData
                    }

                    // Create PlatformImage on main thread to avoid "visual style disabled" warning
                    guard let image = PlatformImage(data: data) else { return nil }
                    // Store the bytes we were served, not a PNG re-encode of them (AITD-345).
                    ImageCache.shared.store(data, image: image, for: requested)
                    return image
                } catch {
                    AppLog.debug("❌ [CachedImageLoader] Failed to load image: \(error)")
                    return nil
                }
            }
            // The shared request intentionally survives one row disappearing, but that row's
            // cancelled waiter must not paint the image after its URL was cleared or replaced.
            guard !_Concurrency.Task.isCancelled, requested == self.url else { return }
            if let loadedImage {
                self.image = loadedImage
            }
            isLoading = false
        }
    }

    func cancel() {
        loadTask?.cancel()
    }

    nonisolated deinit {
        loadTask?.cancel()
    }
}

/// AI-agent endpoints serve SVGs, which PlatformImage cannot decode. Resolve known
/// agent slugs to bundled vector assets before starting a network image load.
enum AgentAvatarAsset {
    nonisolated static func assetName(for url: URL?) -> String? {
        guard let url, url.path.hasPrefix("/api/v1/agent-icon/") else { return nil }
        switch url.lastPathComponent {
        case "copilot": return "ai-copilot"
        default: return nil
        }
    }
}

/// SwiftUI view for cached async images
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader: CachedImageLoader

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder

        if let url = url {
            _loader = StateObject(wrappedValue: CachedImageLoader(url: url))
        } else {
            _loader = StateObject(wrappedValue: CachedImageLoader(url: URL(string: "about:blank")!))
        }
    }

    var body: some View {
        Group {
            if let assetName = AgentAvatarAsset.assetName(for: url) {
                content(Image(assetName))
            } else if let image = loader.image {
                content(Image(platformImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear {
            if let url, AgentAvatarAsset.assetName(for: url) == nil {
                loader.load(url: url)
            }
        }
        // The component follows its url rather than relying on ~25 call sites each remembering an
        // `.id(url)` — exactly one of them ever did, so a changed picture silently did not redraw
        // anywhere else (Task 16f39f36).
        .onChange(of: url) {
            if let url, AgentAvatarAsset.assetName(for: url) == nil {
                loader.load(url: url)
            } else {
                loader.clear()
            }
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

// Convenience initializer matching AsyncImage API
extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}
