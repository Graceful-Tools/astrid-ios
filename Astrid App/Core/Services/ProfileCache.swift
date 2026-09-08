import Foundation

/// Caches user profile data to provide instant loading for user profiles
@MainActor
class ProfileCache {
    static let shared = ProfileCache()

    /// Cache dictionary storing profile data by user ID
    private var cache: [String: CachedProfile] = [:]

    /// Cached profile with timestamp for expiration
    private struct CachedProfile {
        let profile: UserProfileResponse
        let timestamp: Date

        /// Cache is valid for 1 minute (reduced from 5 minutes for fresher stats)
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 60
        }
    }

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Cache Operations

    /// Get cached profile if available and not expired
    func getCachedProfile(userId: String) -> UserProfileResponse? {
        guard let cached = cache[userId], !cached.isExpired else {
            return nil
        }
        return cached.profile
    }

    /// Store profile in cache
    func cacheProfile(_ profile: UserProfileResponse, userId: String) {
        cache[userId] = CachedProfile(profile: profile, timestamp: Date())
    }

    /// Clear cached profile for a user
    func clearCache(userId: String) {
        cache.removeValue(forKey: userId)
    }

    /// Clear all cached profiles
    func clearAllCache() {
        cache.removeAll()
    }

    // MARK: - Prefetch

    /// Prefetch profile data in background for instant loading later
    func prefetchProfile(userId: String) async {
        // Don't prefetch if we already have a valid cached profile
        if let cached = cache[userId], !cached.isExpired {
            AppLog.debug("📋 [ProfileCache] Profile already cached for user: \(userId)")
            return
        }

        AppLog.debug("🔄 [ProfileCache] Prefetching profile for user: \(userId)")

        do {
            let profile: UserProfileResponse = try await apiClient.request(.userProfile(userId: userId))
            cacheProfile(profile, userId: userId)
            AppLog.debug("✅ [ProfileCache] Profile prefetched and cached for user: \(userId)")
        } catch {
            AppLog.debug("❌ [ProfileCache] Failed to prefetch profile: \(error)")
            // Silent failure - prefetch is opportunistic
        }
    }

    /// Load profile with cache support
    func loadProfile(userId: String) async throws -> UserProfileResponse {
        // Check cache first
        if let cachedProfile = getCachedProfile(userId: userId) {
            AppLog.debug("⚡️ [ProfileCache] Using cached profile for user: \(userId)")
            return cachedProfile
        }

        // Load from API if not cached
        AppLog.debug("🌐 [ProfileCache] Loading profile from API for user: \(userId)")
        let profile: UserProfileResponse = try await apiClient.request(.userProfile(userId: userId))
        cacheProfile(profile, userId: userId)
        return profile
    }
}
