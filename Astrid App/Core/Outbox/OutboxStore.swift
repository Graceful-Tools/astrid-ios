import Foundation

/// Durable, atomic persistence for the Outbox journal.
///
/// File-backed JSON (not CoreData) on purpose: the journal holds small,
/// self-contained payloads (references, not file bytes), and a flat file keeps
/// the high-risk runner off the shared CoreData model — no schema migration to
/// get wrong. The interface hides the medium, so it can move to CoreData later
/// without touching the runner.
final class OutboxStore {

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
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([OutboxEntry].self, from: data)) ?? []
    }

    func save(_ entries: [OutboxEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        // Ensure the directory exists, then write atomically (temp + rename) so a
        // crash mid-write can't corrupt the journal.
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
