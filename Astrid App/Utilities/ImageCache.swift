import Foundation
import UIKit
import SwiftUI
import Combine

/// In-memory and disk image cache for fast loading
class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        // Setup memory cache limits
        memoryCache.countLimit = 100 // Max 100 images in memory
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB memory limit

        // Setup disk cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("ListImageCache", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        print("📦 [ImageCache] Initialized with cache directory: \(cacheDirectory.path)")
    }

    /// Get image from cache (memory first, then disk) - synchronous version for main thread
    /// WARNING: Only call from main thread to avoid "visual style disabled" warnings
    func get(url: URL) -> UIImage? {
        // Check memory cache first
        if let cached = memoryCache.object(forKey: url as NSURL) {
            print("✅ [ImageCache] Memory hit: \(url.lastPathComponent)")
            return cached
        }

        // Check disk cache
        let fileURL = diskCacheURL(for: url)
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // Store in memory cache for next time
            memoryCache.setObject(image, forKey: url as NSURL)
            print("💾 [ImageCache] Disk hit: \(url.lastPathComponent)")
            return image
        }

        return nil
    }

    /// Get image from cache asynchronously - safe to call from background
    /// Returns nil if not in cache, otherwise loads from disk on background and creates UIImage on main thread
    func getAsync(url: URL) async -> UIImage? {
        // Check memory cache first (thread-safe)
        if let cached = memoryCache.object(forKey: url as NSURL) {
            print("✅ [ImageCache] Memory hit: \(url.lastPathComponent)")
            return cached
        }

        // Read data from disk on current thread (background-safe)
        let fileURL = diskCacheURL(for: url)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        // Create UIImage on main thread to avoid "visual style disabled" warning
        return await MainActor.run {
            guard let image = UIImage(data: data) else { return nil as UIImage? }
            memoryCache.setObject(image, forKey: url as NSURL)
            print("💾 [ImageCache] Disk hit: \(url.lastPathComponent)")
            return image
        }
    }

    /// Store image in both memory and disk cache - synchronous version
    /// WARNING: Only call from main thread to avoid "visual style disabled" warnings
    func set(_ image: UIImage, for url: URL) {
        // Store in memory cache
        memoryCache.setObject(image, forKey: url as NSURL)

        // Store in disk cache
        let fileURL = diskCacheURL(for: url)
        if let data = image.pngData() {
            try? data.write(to: fileURL)
            print("💾 [ImageCache] Cached: \(url.lastPathComponent) (\(data.count / 1024) KB)")
        }
    }

    /// Store image in cache asynchronously - safe to call from background
    /// Encodes image on main thread, writes to disk on background
    func setAsync(_ image: UIImage, for url: URL) async {
        // Store in memory cache (thread-safe)
        memoryCache.setObject(image, forKey: url as NSURL)

        // Encode image on main thread to avoid "visual style disabled" warning
        let data = await MainActor.run {
            image.pngData()
        }

        guard let data else { return }

        // Write to disk on background thread
        let fileURL = diskCacheURL(for: url)
        try? data.write(to: fileURL)
        print("💾 [ImageCache] Cached: \(url.lastPathComponent) (\(data.count / 1024) KB)")
    }

    /// Clear all caches
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("🗑️ [ImageCache] Cache cleared")
    }

    /// Clear memory cache only (keeps disk cache for offline)
    /// Call this when app becomes active to refresh images from server
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        print("🗑️ [ImageCache] Memory cache cleared")
    }

    /// Remove a specific URL from cache
    func remove(url: URL) {
        memoryCache.removeObject(forKey: url as NSURL)
        let fileURL = diskCacheURL(for: url)
        try? fileManager.removeItem(at: fileURL)
        print("🗑️ [ImageCache] Removed: \(url.lastPathComponent)")
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
        print("🗑️ [ImageCache] Secure files cache cleared")
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
    @Published var image: UIImage?
    @Published var isLoading = false

    private let url: URL
    private var loadTask: _Concurrency.Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    func load() {
        // Check cache first (on main thread since we're @MainActor)
        if let cached = ImageCache.shared.get(url: url) {
            self.image = cached
            return
        }

        // Load from network
        isLoading = true
        loadTask = _Concurrency.Task {
            // First check disk cache asynchronously (safe from background)
            if let cached = await ImageCache.shared.getAsync(url: url) {
                self.image = cached
                isLoading = false
                return
            }

            do {
                let data: Data

                // Check if this is a secure-files URL that requires authentication.
                // Match both /api/secure-files/ (older stored URLs) and /api/v1/secure-files/
                // (new emissions) so cached attachments from before the v1 cutover keep loading.
                if url.path.contains("/api/secure-files/") || url.path.contains("/api/v1/secure-files/") {
                    var request = URLRequest(url: url)
                    // Add session cookie for authentication
                    if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                    }
                    let (responseData, _) = try await URLSession.shared.data(for: request)
                    data = responseData
                } else {
                    // Public URL, no auth needed
                    let (responseData, _) = try await URLSession.shared.data(from: url)
                    data = responseData
                }

                // Create UIImage on main thread to avoid "visual style disabled" warning
                let loadedImage = UIImage(data: data)
                if let loadedImage {
                    // Cache asynchronously (encodes on main thread, writes on background)
                    await ImageCache.shared.setAsync(loadedImage, for: url)
                    self.image = loadedImage
                }
            } catch {
                print("❌ [CachedImageLoader] Failed to load image: \(error)")
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
            if let image = loader.image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear {
            if url != nil {
                loader.load()
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
