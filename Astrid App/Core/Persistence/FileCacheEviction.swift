//  FileCacheEviction.swift
//  Which cached files to drop when a directory cache outgrows its budget (task AITD-344).
//
//  `AttachmentService` wrote every secure file the user ever previewed into
//  `Caches/DownloadedAttachments/<fileId>` and never removed one except on attachment deletion
//  or sign-out. iOS may purge `Caches/` under disk pressure; macOS does not, and the Mac is
//  where this account's local stores had already reached hundreds of megabytes.
//
//  Pure, so the policy can be tested without a filesystem — and so it can be reused by the other
//  unbounded directory cache (`ImageCache`, task AITD-345) rather than being written twice.
import Foundation

struct FileCacheEntry: Equatable {
    let id: String
    let size: Int
    /// Last access where the platform records it, falling back to modification date.
    let lastAccess: Date
}

enum FileCacheEviction {

    /// The ids to delete so the total falls to `cap` or below, least-recently-accessed first.
    ///
    /// Returns them in deletion order. An empty result means nothing needs to go — the common
    /// case, and it must stay cheap because this runs after every cache write.
    static func idsToEvict(_ entries: [FileCacheEntry], cap: Int) -> [String] {
        let total = entries.reduce(0) { $0 + $1.size }
        guard total > cap else { return [] }

        // Oldest access first. Ties break on id so the outcome is deterministic — a test that
        // depends on which of two equally-old files went would otherwise be flaky.
        let ordered = entries.sorted {
            $0.lastAccess == $1.lastAccess ? $0.id < $1.id : $0.lastAccess < $1.lastAccess
        }

        var remaining = total
        var evicted: [String] = []
        for entry in ordered where remaining > cap {
            evicted.append(entry.id)
            remaining -= entry.size
        }
        return evicted
    }

    /// Apply the policy to a directory of flat files. Returns how many were removed.
    ///
    /// The filesystem half that `ImageCache` and `DownloadedAttachmentCache` each carried a copy
    /// of. Access date is the right signal but is not always recorded (noatime volumes, and it is
    /// unreliable on the simulator), so fall back to modification date rather than treating an
    /// unknown file as infinitely old and evicting it first.
    @discardableResult
    static func sweep(directory: URL, cap: Int, fileManager: FileManager = .default) -> Int {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        else { return 0 }

        let entries: [FileCacheEntry] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { return nil }
            let accessed = values.contentAccessDate ?? values.contentModificationDate ?? Date()
            return FileCacheEntry(id: url.lastPathComponent, size: size, lastAccess: accessed)
        }

        let doomed = idsToEvict(entries, cap: cap)
        for id in doomed {
            try? fileManager.removeItem(at: directory.appendingPathComponent(id))
        }
        return doomed.count
    }
}
