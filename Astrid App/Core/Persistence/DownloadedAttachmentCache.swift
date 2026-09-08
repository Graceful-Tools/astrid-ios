//  DownloadedAttachmentCache.swift
//  The on-disk cache of secure files the user has previewed.
//
//  Extracted from `AttachmentService` (task AITD-344), which had grown past the 1,000-line
//  ceiling `SourceFileSizeGuardTests` now enforces. Raising the ceiling would have been the
//  reflex that turned six oversized files into nine; the cache is a cohesive unit with a
//  directory, a budget and an eviction rule, so it comes out instead.
//
//  Two behaviours worth stating, because both were bugs:
//
//  1. **It is bounded.** Every previewed file used to be written here and nothing but attachment
//     deletion or sign-out ever removed one. iOS may purge `Caches/` under disk pressure; macOS
//     does not, and the Mac is where this account's local stores had already reached hundreds of
//     megabytes. `enforceLimit` drops least-recently-used files past the budget, at launch and
//     after every write.
//  2. **Preview paths are per FILE, not per NAME.** `previewURL` keys its directory on the file
//     id. Keyed on the name alone, two attachments both called "photo.png" resolved to one path
//     — the second write clobbered the first, and once previews download concurrently it is a
//     race, with one task copying over what another is reading.
import Foundation

final class DownloadedAttachmentCache {

    /// How much of the user's disk this may occupy.
    static let defaultByteLimit = 200 * 1024 * 1024

    private let directory: URL
    private let previewRoot: URL
    private let byteLimit: Int
    private let fileManager: FileManager

    init(directory: URL,
         previewRoot: URL,
         byteLimit: Int = DownloadedAttachmentCache.defaultByteLimit,
         fileManager: FileManager = .default) {
        self.directory = directory
        self.previewRoot = previewRoot
        self.byteLimit = byteLimit
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // A cache that grew before the limit existed is exactly the case to fix, so sweep at
        // construction rather than waiting for the next write.
        enforceLimit()
    }

    // MARK: - Reading

    func data(for fileId: String) -> Data? {
        let path = path(for: fileId)
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        return try? Data(contentsOf: path)
    }

    func contains(_ fileId: String) -> Bool {
        fileManager.fileExists(atPath: path(for: fileId).path)
    }

    /// A copy of the cached file under its display name, ready for QuickLook — which picks its
    /// previewer from the extension, so the name has to survive.
    func previewCopy(fileId: String, fileName: String) -> URL? {
        let cached = path(for: fileId)
        guard fileManager.fileExists(atPath: cached.path) else { return nil }

        let destination = previewURL(fileId: fileId, fileName: fileName)
        do {
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: cached, to: destination)
            return destination
        } catch {
            AppLog.debug("⚠️ [DownloadedAttachmentCache] Failed to prepare preview copy: \(error)")
            return nil
        }
    }

    /// A previewable path for one file, isolated from every other file.
    ///
    /// The id is server-supplied like the name, so it goes through the same sanitiser — see
    /// `AttachmentFileName`, and task AITD-312 for why that matters.
    func previewURL(fileId: String, fileName: String) -> URL {
        let directory = previewRoot
            .appendingPathComponent(AttachmentFileName.sanitized(fileId), isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return AttachmentFileName.temporaryURL(in: directory, for: fileName)
    }

    // MARK: - Writing

    func store(_ data: Data, for fileId: String) {
        do {
            try data.write(to: path(for: fileId))
            AppLog.debug("💾 [DownloadedAttachmentCache] Cached \(fileId) (\(data.count) bytes)")
            enforceLimit()
        } catch {
            AppLog.debug("⚠️ [DownloadedAttachmentCache] Failed to cache download: \(error)")
        }
    }

    func remove(_ fileId: String) {
        try? fileManager.removeItem(at: path(for: fileId))
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Eviction

    /// Drop least-recently-used files until the cache is inside its budget.
    ///
    /// The policy is `FileCacheEviction`, tested on its own; this is only the filesystem around
    /// it. Running after every write is the part that matters — a sweep only at launch would let
    /// one long session grow without limit, which is the shape of the original bug.
    func enforceLimit() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }

        let entries: [FileCacheEntry] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { return nil }
            // Access date is the right signal but is not always recorded (noatime volumes, and
            // it is unreliable on the simulator), so fall back to modification date rather than
            // treating an unknown file as infinitely old and evicting it first.
            let accessed = values.contentAccessDate ?? values.contentModificationDate ?? Date()
            return FileCacheEntry(id: url.lastPathComponent, size: size, lastAccess: accessed)
        }

        let doomed = FileCacheEviction.idsToEvict(entries, cap: byteLimit)
        guard !doomed.isEmpty else { return }
        for id in doomed {
            try? fileManager.removeItem(at: directory.appendingPathComponent(id))
        }
        AppLog.debug("🧹 [DownloadedAttachmentCache] Evicted \(doomed.count) files over the \(byteLimit) byte cap")
    }

    // MARK: -

    private func path(for fileId: String) -> URL {
        directory.appendingPathComponent(fileId)
    }
}
