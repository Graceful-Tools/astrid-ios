import Foundation

/// Durable, atomic persistence for the Outbox journal.
///
/// File-backed JSON (not CoreData) on purpose: the journal holds small,
/// self-contained payloads (references, not file bytes), and a flat file keeps
/// the high-risk runner off the shared CoreData model — no schema migration to
/// get wrong. The interface hides the medium, so it can move to CoreData later
/// without touching the runner.
nonisolated final class OutboxStore: Sendable {

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Production location: Application Support/outbox.json.
    static func defaultFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("outbox.json")
    }

    func load() -> [OutboxEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }  // no file yet
        if let decoded = try? JSONDecoder().decode([OutboxEntry].self, from: data) {
            return decoded
        }
        // The file exists but won't decode. Don't silently drop the queued writes:
        // preserve the corrupt journal alongside (".corrupt") for recovery, then
        // start fresh so the Outbox isn't wedged.
        let backup = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return []
    }

    func save(_ entries: [OutboxEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        // Ensure the directory exists, then write atomically (temp + rename) so a
        // crash mid-write can't corrupt the journal. File protection encrypts the
        // payloads at rest while still allowing background drains after first
        // unlock.
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
