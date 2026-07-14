//  ThumbnailCache.swift
//  Moved out of Views/Components/AttachmentThumbnail.swift so AttachmentService
//  (shared service layer) can use it on macOS. Image cache, not a view.

import Foundation

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [String: PlatformImage] = [:]

    func get(_ fileId: String) -> PlatformImage? {
        return cache[fileId]
    }

    func set(_ image: PlatformImage, for fileId: String) {
        cache[fileId] = image
    }

    func has(_ fileId: String) -> Bool {
        return cache[fileId] != nil
    }

    /// Copy cache entry when temp ID is replaced with real ID
    func alias(from tempId: String, to realId: String) {
        if let image = cache[tempId] {
            cache[realId] = image
            print("🖼️ [ThumbnailCache] Aliased \(tempId) -> \(realId)")
        }
    }
}
