import Foundation
import Combine
import UIKit

enum AstridFeature: String, Codable, CaseIterable {
    case googleTasks = "google_tasks"
}

struct FeatureFlagSnapshot: Codable, Equatable {
    var version: Int
    var features: [String: Bool]
    var updatedAt: Date

    static func defaultValue(for feature: AstridFeature) -> Bool {
        switch feature {
        case .googleTasks: false
        }
    }

    func isEnabled(_ feature: AstridFeature) -> Bool {
        features[feature.rawValue] ?? Self.defaultValue(for: feature)
    }
}

struct EffectiveFeaturesResponse: Codable {
    let version: Int
    let features: [String: Bool]
}

struct FeatureFlagLaunchDecision: Equatable {
    let shouldRefresh: Bool
    let nextLaunchCount: Int
}

enum FeatureFlagLaunchPolicy {
    nonisolated static let defaultTTL: TimeInterval = 15 * 60

    nonisolated static func decision(
        previousLaunchCount: Int,
        cacheUpdatedAt: Date?,
        now: Date,
        ttl: TimeInterval = defaultTTL
    ) -> FeatureFlagLaunchDecision {
        let next = previousLaunchCount + 1
        guard previousLaunchCount > 0 else {
            return FeatureFlagLaunchDecision(shouldRefresh: false, nextLaunchCount: next)
        }
        let stale = cacheUpdatedAt.map { now.timeIntervalSince($0) >= ttl } ?? true
        return FeatureFlagLaunchDecision(shouldRefresh: stale, nextLaunchCount: next)
    }
}

/// Cached, user-scoped remote feature entitlements. Initialization performs
/// local reads only; networking is scheduled after the first frame and never
/// occurs on the first-ever app launch.
@MainActor
final class FeatureFlagService: ObservableObject {
    static let shared = FeatureFlagService()
    private static let launchCountKey = "featureFlags.launchCount"
    private static let refreshEligibleKey = "featureFlags.refreshEligibleThisLaunch"

    @Published private(set) var snapshot = FeatureFlagSnapshot(version: 0, features: [:], updatedAt: .distantPast)
    private var isRefreshing = false
    private var observers: [NSObjectProtocol] = []

    static func recordAppLaunch(defaults: UserDefaults = .standard) {
        let previous = defaults.integer(forKey: launchCountKey)
        defaults.set(previous + 1, forKey: launchCountKey)
        defaults.set(previous > 0, forKey: refreshEligibleKey)
    }

    private init() {
        if let userId = UserDefaults.standard.string(forKey: Constants.UserDefaults.userId) {
            loadCachedSnapshot(userId: userId)
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .featureFlagsUpdated, object: nil, queue: .main) { [weak self] note in
            let version = note.userInfo?["version"] as? Int ?? 0
            _Concurrency.Task { @MainActor [weak self] in
                guard let self, version > self.snapshot.version else { return }
                await self.refreshIfStale(force: true)
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in await self?.refreshIfStale() }
        })
    }

    func isEnabled(_ feature: AstridFeature) -> Bool {
        snapshot.isEnabled(feature)
    }

    func refreshIfStale(userId explicitUserId: String? = nil, force: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: Self.refreshEligibleKey) else { return }
        let userId = explicitUserId
            ?? AuthManager.shared.currentUser?.id
            ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userId)
        guard let userId, !isRefreshing else { return }
        loadCachedSnapshot(userId: userId)
        if !force, Date().timeIntervalSince(snapshot.updatedAt) < FeatureFlagLaunchPolicy.defaultTTL { return }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await AstridAPIClient.shared.getEffectiveFeatures()
            let next = FeatureFlagSnapshot(version: response.version, features: response.features, updatedAt: Date())
            snapshot = next
            if let data = try? JSONEncoder().encode(next) {
                UserDefaults.standard.set(data, forKey: cacheKey(userId: userId))
            }
            NotificationCenter.default.post(name: .featureFlagsDidChange, object: nil)
        } catch {
            // Cached/default flags remain authoritative while offline.
        }
    }

    func clearCache(userId: String?) {
        if let userId { UserDefaults.standard.removeObject(forKey: cacheKey(userId: userId)) }
        snapshot = FeatureFlagSnapshot(version: 0, features: [:], updatedAt: .distantPast)
    }

    private func loadCachedSnapshot(userId: String) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(userId: userId)),
              let cached = try? JSONDecoder().decode(FeatureFlagSnapshot.self, from: data) else { return }
        if cached != snapshot { snapshot = cached }
    }

    private func cacheKey(userId: String) -> String { "featureFlags.snapshot.\(userId)" }
}

extension AstridAPIClient {
    func getEffectiveFeatures() async throws -> EffectiveFeaturesResponse {
        try await request(method: "GET", path: "/api/v1/features")
    }
}

extension Notification.Name {
    static let featureFlagsUpdated = Notification.Name("featureFlagsUpdated")
    static let featureFlagsDidChange = Notification.Name("featureFlagsDidChange")
}
