import Foundation

/// Cache for AI agents to support offline mode
/// Stores AI agents locally so they're available when the API is unreachable
final class AIAgentCache {
    static let shared = AIAgentCache()

    private let userDefaults = UserDefaults.standard
    private let cacheKey = "cached_ai_agents"
    private let cacheTimestampKey = "cached_ai_agents_timestamp"

    /// Cache duration: 1 hour (refresh frequently to pick up image/name changes)
    private let cacheDuration: TimeInterval = 1 * 60 * 60

    /// The decoded agents, and the stored timestamp they were decoded from.
    ///
    /// `load()` used to read `UserDefaults` and JSON-DECODE on every call, and four of its ten
    /// call sites are inside SwiftUI view bodies — `MacLeadingControlButton.face` most of all,
    /// which runs for every board card on every layout pass. A `cpu_resource.diag` from
    /// TestFlight build 901 caught the result: 90s of CPU over 114s, 79% sustained, at idle.
    ///
    /// Keyed on the TIMESTAMP rather than simply held, so a write from another process — the
    /// share extension shares this UserDefaults — still invalidates it. The cheap
    /// `double(forKey:)` read stays on every call; only the expensive part is skipped.
    private var memo: [User]?
    private var memoTimestamp: TimeInterval = -1

    /// How many times the payload has actually been decoded. Diagnostics: the whole point of
    /// the memo is that this stops climbing, and that is not otherwise observable.
    private(set) var decodeCount = 0

    /// `load()` is called from views (main actor) and from `ChatService` (background), so the
    /// memo needs guarding.
    private let lock = NSLock()

    private init() {}

    /// Save AI agents to local cache
    func save(_ agents: [User]) {
        guard !agents.isEmpty else { return }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(agents)
            let now = Date().timeIntervalSince1970
            userDefaults.set(data, forKey: cacheKey)
            userDefaults.set(now, forKey: cacheTimestampKey)
            // Adopt what we just wrote rather than invalidating: the next read is usually
            // immediate, and re-decoding our own array would be the thing this exists to avoid.
            lock.lock()
            memo = agents
            memoTimestamp = now
            lock.unlock()
            print("✅ [AIAgentCache] Saved \(agents.count) AI agents to cache")
        } catch {
            print("❌ [AIAgentCache] Failed to save agents: \(error)")
        }
    }

    /// Load AI agents from local cache
    /// Returns nil if cache is empty or expired
    func load() -> [User]? {
        // The timestamp first, and on its own: it is a cheap scalar read, it decides expiry,
        // and it tells us whether the memo is still good — all without touching the payload.
        let timestamp = userDefaults.double(forKey: cacheTimestampKey)

        let cacheAge = Date().timeIntervalSince1970 - timestamp
        if timestamp > 0 && cacheAge > cacheDuration {
            clear()
            return nil
        }

        lock.lock()
        if let memo, memoTimestamp == timestamp, timestamp > 0 {
            lock.unlock()
            return memo
        }
        lock.unlock()

        // Check if cache exists
        guard let data = userDefaults.data(forKey: cacheKey) else {
            // Silent return - no agents cached is normal state
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let agents = try decoder.decode([User].self, from: data)
            lock.lock()
            decodeCount += 1
            memo = agents
            memoTimestamp = timestamp
            lock.unlock()
            return agents
        } catch {
            print("❌ [AIAgentCache] Failed to load agents: \(error)")
            clear()
            return nil
        }
    }

    /// Clear the cache
    func clear() {
        userDefaults.removeObject(forKey: cacheKey)
        userDefaults.removeObject(forKey: cacheTimestampKey)
        lock.lock()
        memo = nil
        memoTimestamp = -1
        lock.unlock()
        // Silent clear - this is routine maintenance
    }
}
