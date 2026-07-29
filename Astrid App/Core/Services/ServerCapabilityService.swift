import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "ServerCapabilities")

/// Tracks what the connected deployment offers, so the UI can hide entry points for
/// services this server does not serve.
///
/// Task 97208a72. Deliberately simple next to FeatureFlagService: capabilities are
/// constant for a given deployment (they are build-time configuration on the server),
/// so there is no per-user evaluation, no rollout percentage and no cache versioning —
/// just a refresh on launch and whenever the server URL changes.
///
/// Presentation only. Every capability is enforced on the server's own routes; this
/// exists so the user is not offered a button that answers 404.
@MainActor
final class ServerCapabilityService: ObservableObject {
    static let shared = ServerCapabilityService()

    /// Starts permissive so nothing is hidden before the first fetch completes.
    @Published private(set) var capabilities: ServerCapabilities = .permissive

    private var isRefreshing = false
    private var lastFetchedBaseURL: String?

    private init() {}

    /// Fetch capabilities for the current server, unless a fetch is already in flight.
    ///
    /// Failure leaves the previous value in place (permissive on a cold start). An older
    /// deployment has no such endpoint and will 404; that is not an error worth
    /// surfacing, and hiding every integration because one request failed would be worse
    /// than showing one that turns out to be unavailable.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let baseURL = Constants.API.baseURL
        do {
            let fetched = try await AstridAPIClient.shared.getServerCapabilities()
            capabilities = fetched
            // Cache the brand's voice so reminders scheduled offline still speak in it.
            // Only written on a SUCCESSFUL fetch: a failed request must leave the last
            // known voice alone rather than reverting a partner's app to Astrid's nags
            // the first time the network is away. Task 97208a72.
            BrandCopyStore.shared.store(fetched.copy)
            lastFetchedBaseURL = baseURL
            logger.debug("Loaded server capabilities from \(baseURL, privacy: .public)")
        } catch {
            logger.debug("Could not load server capabilities: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refresh when the app points at a different server than the one we last asked.
    func refreshIfServerChanged() async {
        guard lastFetchedBaseURL != Constants.API.baseURL else { return }
        await refresh()
    }
}
