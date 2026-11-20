import CryptoKit
import Foundation

// MARK: - Empathy-state art (ADEV-127)
//
// The octopus acting out a board column's state, in five metaphors (race, wall, chef, garden,
// hike). The hi-fi frames live on the server (`GET /api/v1/empathy-art`, astrid-web ADEV-142) and
// are fetched quietly when the device is idle on an unmetered connection. The built-in character
// stays the default: a frame is drawn only once its whole metaphor is on disk, so nothing waits
// on the network and a board never mixes hi-fi and built-in art across its columns.
//
// The rotation and column rules are a cross-platform contract: astrid-web
// `contracts/fixtures/empathy-art.json`, copied into `Astrid AppTests/Tests/Fixtures/`.

/// A board column's state, as the art names it.
nonisolated enum EmpathyArtState: String, CaseIterable, Sendable {
    case inbox, ready, doing, waiting, done
}

nonisolated enum EmpathyArt {
    /// The server's metaphors, in its order — the order the rotation indexes into. A cached
    /// manifest's list wins; this is only the fallback the fixture pins.
    static let defaultMetaphors = ["race", "wall", "chef", "garden", "hike"]

    /// How often an idle device asks the server whether the art changed.
    static let recheckInterval: TimeInterval = 12 * 60 * 60

    /// FNV-1a 32 over the UTF-8 bytes — the hash the server's rule uses.
    static func fnv1a32(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    /// Whole UTC days since 1970 — the day turns over at 00:00 UTC on every client.
    static func daysSinceEpochUTC(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000 / 86_400_000).rounded(.down))
    }

    /// Today's metaphor for a list: `metaphors[(fnv1a32(listId) + days) % count]`, summed in 64
    /// bits so it never wraps the way a 32-bit sum would.
    static func metaphor(listId: String, at date: Date, metaphors: [String]) -> String? {
        guard !metaphors.isEmpty else { return nil }
        let sum = Int64(fnv1a32(listId)) + Int64(daysSinceEpochUTC(date))
        let index = Int(((sum % Int64(metaphors.count)) + Int64(metaphors.count)) % Int64(metaphors.count))
        return metaphors[index]
    }

    /// The fixture's column rule: Done wins, Inbox is no role, ready/doing/waiting are
    /// themselves, a custom column has no frame.
    static func state(completed: Bool, statusRole: String?) -> EmpathyArtState? {
        if completed { return .done }
        guard let statusRole else { return .inbox }
        switch statusRole {
        case "ready": return .ready
        case "doing": return .doing
        case "waiting": return .waiting
        default: return nil
        }
    }

    /// The same rule for a board column, whose id is its role.
    static func state(for column: ProjectBoardColumn) -> EmpathyArtState? {
        switch column.kind {
        case .done: return .done
        case .inbox: return .inbox
        case .status: return state(completed: false, statusRole: column.id)
        }
    }

    /// The art is Astrid's octopus, so only a build showing Astrid's own character may draw it —
    /// a partner's board showing our mascot is the leak `Brand.characterImage` exists to stop.
    static func brandMayShow(characterImage: String?) -> Bool {
        characterImage == Brand.astridCharacterAsset
    }

    /// "Downtime": Wi-Fi or Ethernet, and not Low Data Mode. Never spend someone's cellular plan
    /// on art the app does not need.
    static func isIdleNetwork(type: NetworkMonitor.ConnectionType, constrained: Bool) -> Bool {
        guard !constrained else { return false }
        return type == .wifi || type == .ethernet
    }

    static func isDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= recheckInterval
    }
}

// MARK: - Wire shape

/// `GET /api/v1/empathy-art` (astrid-web `docs/API_CONTRACT.md`).
nonisolated struct EmpathyArtManifest: Codable, Equatable, Sendable {
    struct Frame: Codable, Equatable, Sendable {
        let metaphor: String
        let state: String
        let url: String
        let sha256: String
        let bytes: Int
    }

    let version: Int
    let revision: String
    let metaphors: [String]
    let states: [String]
    let frames: [Frame]

    /// The manifest version this client understands. A newer one is ignored and the built-in
    /// art stays, rather than guessing at a shape that changed.
    static let supportedVersion = 1
    var isSupported: Bool { version == Self.supportedVersion }
}

// MARK: - On-disk store

/// The cached frames and the manifest they came from, in Caches (the system may purge it; the
/// built-in art is the fallback, so that costs nothing). Its own directory rather than
/// `ImageCache`, whose LRU sweep would evict a set piecemeal.
nonisolated final class EmpathyArtStore: @unchecked Sendable {
    let directory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cachedManifest: EmpathyArtManifest?

    init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        cachedManifest = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode(EmpathyArtManifest.self, from: $0) }
    }

    static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("EmpathyArt", isDirectory: true)
    }

    private var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    private func frameURL(metaphor: String, state: EmpathyArtState) -> URL {
        // Names come from the server; keep them to a safe file name.
        let safe = metaphor.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appendingPathComponent("\(safe)-\(state.rawValue).img")
    }

    private func checksumURL(metaphor: String, state: EmpathyArtState) -> URL {
        frameURL(metaphor: metaphor, state: state).appendingPathExtension("sha256")
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var manifest: EmpathyArtManifest? { lock.withLock { cachedManifest } }
    var metaphors: [String] { manifest?.metaphors ?? [] }
    var revision: String? { manifest?.revision }

    func saveManifest(_ manifest: EmpathyArtManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
        lock.withLock { cachedManifest = manifest }
    }

    /// Is this exact frame (by checksum) already on disk?
    func has(metaphor: String, state: EmpathyArtState, sha256: String) -> Bool {
        guard let stored = try? String(contentsOf: checksumURL(metaphor: metaphor, state: state), encoding: .utf8)
        else { return false }
        return stored == sha256.lowercased() && fileManager.fileExists(atPath: frameURL(metaphor: metaphor, state: state).path)
    }

    /// Keep a downloaded frame only when it is the bytes the manifest promised.
    @discardableResult
    func save(_ data: Data, metaphor: String, state: EmpathyArtState, sha256: String) -> Bool {
        guard Self.sha256Hex(data) == sha256.lowercased() else { return false }
        do {
            try data.write(to: frameURL(metaphor: metaphor, state: state), options: .atomic)
            try sha256.lowercased().write(to: checksumURL(metaphor: metaphor, state: state),
                                          atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    func frameData(metaphor: String, state: EmpathyArtState) -> Data? {
        try? Data(contentsOf: frameURL(metaphor: metaphor, state: state))
    }

    /// Every state of this metaphor is on disk — the condition for drawing any of them.
    func isComplete(metaphor: String) -> Bool {
        EmpathyArtState.allCases.allSatisfy {
            fileManager.fileExists(atPath: frameURL(metaphor: metaphor, state: $0).path)
        }
    }

    func removeAll() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        lock.withLock { cachedManifest = nil }
    }
}
