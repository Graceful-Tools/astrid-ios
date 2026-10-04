import AstridCore
import Combine
import Foundation

/// Parses the `astrid://google-tasks/...` callback the backend redirects to after the OAuth
/// flow (task 6745f40f). Pure/testable, separate from the ASWebAuthenticationSession plumbing.
enum GoogleTasksConnectCallback {
    /// An error message if the callback signals failure (path contains "error"), else nil (success).
    static func errorMessage(from callback: URL) -> String? {
        guard callback.path.contains("error") else { return nil }
        return URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "message" })?.value
            ?? "Connection didn't complete."
    }
}

/// Google Tasks sync: the account's connection, links and mode, and when a pass runs. The pass
/// itself is astrid-core's `syncExternal` (AITD-463) — the same one Windows runs — and so is the
/// deletion ledger it reads: the core records a deleted task's twin when it deletes the task.
/// Google has no webhooks — passes run on foreground / SSE nudge / local edit / manual.
@MainActor
final class GoogleTasksSyncService: ObservableObject {
    static let shared = GoogleTasksSyncService()

    @Published var isConnected = false
    @Published var accountEmail: String?
    @Published var links: [ExternalListLinkDTO] = []
    @Published var isSyncing = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?
    @Published var syncMode: GoogleSyncMode = .manual
    @Published var listSuffix: String = ""
    /// Tasklists the user opted OUT of (deleted their mirrored Astrid list
    /// while an all-lists mode was on) — auto-link must not resurrect them.
    @Published var excludedTasklistIds: Set<String> = []


    private let apiClient = AstridAPIClient.shared
    private var core: CoreSession { AppCore.shared.session }
    private var observers: [NSObjectProtocol] = []
    private var syncDebounce: _Concurrency.Task<Void, Never>?

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .externalSyncRefresh, object: nil, queue: .main
        ) { [weak self] note in
            let source = note.userInfo?[LocalMutation.sourceKey] as? String
            guard SyncMutationNudge.shouldSchedule(provider: .google, mutationSource: source) else { return }
            _Concurrency.Task { @MainActor [weak self] in self?.scheduleSync() }
        })
        observers.append(center.addObserver(
            forName: PlatformApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in self?.scheduleSync() }
        })
        // Local writes nudge a debounced sync pass so pushes don't wait for
        // foreground/refresh. Suppress our OWN sync-originated mutations
        // (completed-backfill imports, remote-apply writes tagged source: .google):
        // re-arming a pass on those creates a self-sustaining ~2s loop until the
        // whole history is imported.
        observers.append(center.addObserver(
            forName: LocalMutation.didHappen, object: nil, queue: .main
        ) { [weak self] note in
            let source = note.userInfo?[LocalMutation.sourceKey] as? String
            guard SyncMutationNudge.shouldSchedule(provider: .google, mutationSource: source) else { return }
            _Concurrency.Task { @MainActor [weak self] in self?.scheduleSync() }
        })
        observers.append(center.addObserver(
            forName: .featureFlagsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                if FeatureFlagService.shared.isEnabled(.googleTasks) {
                    await self.refreshStatus()
                    self.scheduleSync()
                } else {
                    self.syncDebounce?.cancel()
                }
            }
        })
    }

    // MARK: - Connection / links

    func refreshStatus() async {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { return }
        do {
            let integrations = try await apiClient.getSyncIntegrations().integrations
            let google = integrations.first { $0.provider == "GOOGLE_TASKS" }
            isConnected = google != nil
            accountEmail = google?.externalAccountId
            syncMode = google?.metadata?.googleSyncMode.flatMap(GoogleSyncMode.init(rawValue:)) ?? .manual
            listSuffix = google?.metadata?.listSuffix ?? ""
            excludedTasklistIds = Set((google?.metadata?.excludedTasklists ?? "").split(separator: ",").map(String.init))
            links = isConnected ? try await apiClient.getGoogleLinks().links : []
        } catch {
            isConnected = false
            links = []
        }
    }

    func authorizeURL() async -> URL? {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { return nil }
        return (try? await apiClient.getGoogleAuthorizeURL().url).flatMap { URL(string: $0) }
    }

    /// Connect Google Tasks via an in-app auth session that auto-dismisses when the backend
    /// callback returns to `astrid://google-tasks/...` — no more stranded web page (task 6745f40f).
    /// Throws on cancel or a backend-reported error (message carried on the callback URL).
    func connect() async throws {
        guard let url = await authorizeURL() else { throw CancellationError() }
        let callback = try await OAuthWebConnector.shared.present(url: url, callbackScheme: "astrid")
        if let message = GoogleTasksConnectCallback.errorMessage(from: callback) {
            throw NSError(domain: "GoogleTasksSyncService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        await refreshStatus()
        scheduleSync()
    }

    func disconnect() async {
        try? await apiClient.disconnectGoogle()
        await refreshStatus()
    }

    func linkList(_ listId: String, tasklistId: String) async throws {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { throw CancellationError() }
        _ = try await apiClient.createGoogleLink(astridListId: listId, tasklistId: tasklistId)
        // Manually linking clears any earlier opt-out for this tasklist.
        if excludedTasklistIds.contains(tasklistId) {
            excludedTasklistIds.remove(tasklistId)
            try? await apiClient.updateIntegrationMetadata(
                provider: "GOOGLE_TASKS",
                metadata: ["excludedTasklists": excludedTasklistIds.joined(separator: ",")])
        }
        await refreshStatus()
        scheduleSync()
    }

    func createAstridListAndLink(tasklistId: String, tasklistName: String) async throws {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { throw CancellationError() }
        let created = try await ListService.shared.createList(name: tasklistName)
        guard !created.id.hasPrefix("temp_") else {
            throw NSError(
                domain: "GoogleTasksSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't create list \"\(tasklistName)\" while offline."])
        }
        try await linkList(created.id, tasklistId: tasklistId)
    }

    @discardableResult
    func createGoogleTasklistAndLink(listId: String, listName: String) async throws -> GoogleTasklistDTO {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { throw CancellationError() }
        let tasklist = try await apiClient.createGoogleTasklist(title: listName)
        try await linkList(listId, tasklistId: tasklist.id)
        return tasklist
    }

    /// Called when the user deletes an Astrid list that was linked to a Google
    /// tasklist: remember the tasklist as opted-out so the all-lists auto-link
    /// doesn't immediately resurrect the deleted list.
    func noteMirroredListDeleted(tasklistId: String) async {
        excludedTasklistIds.insert(tasklistId)
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { return }
        try? await apiClient.updateIntegrationMetadata(
            provider: "GOOGLE_TASKS",
            metadata: ["excludedTasklists": excludedTasklistIds.joined(separator: ",")])
    }

    /// Sign-out: drop all in-memory state for the departing account.
    func resetForSignOut() {
        isConnected = false
        accountEmail = nil
        links = []
        isSyncing = false
        lastSyncedAt = nil
        lastError = nil
        syncMode = .manual
        listSuffix = ""
        excludedTasklistIds = []
        syncDebounce?.cancel()
    }

    func unlink(_ linkId: String) async {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { return }
        try? await apiClient.deleteGoogleLink(linkId: linkId)
        await refreshStatus()
    }

    /// Persist the sync mode + suffix server-side (Integration.metadata) so the
    /// choice follows the account across devices, then sync (auto-link runs at
    /// the start of the pass).
    func setSyncMode(_ mode: GoogleSyncMode, suffix: String) async {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { return }
        syncMode = mode
        listSuffix = suffix
        var command = CoreCommand(kind: "setGoogleSyncMode")
        command.set("mode", mode.rawValue)
        command.set("suffix", suffix)
        try? await core.run(command)
        scheduleSync()
    }

    // MARK: - Sync

    private var rerunAfterPass = false
    /// When the last pass STARTED, for `SyncPassFloor`.
    private var lastPassStarted: Date?

    func scheduleSync() {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else {
            syncDebounce?.cancel()
            return
        }
        guard isConnected else { return }
        guard !links.isEmpty || syncMode != .manual else { return }
        if isSyncing { rerunAfterPass = true; return }  // don't drop mid-pass nudges
        syncDebounce?.cancel()
        syncDebounce = _Concurrency.Task { @MainActor [weak self] in
            // Debounce plus the floor remainder — see SyncPassScheduler.
            guard await SyncPassScheduler.waitForNextPass(lastPassStarted: self?.lastPassStarted) else { return }
            await self?.syncAll()
        }
    }

    func syncAll() async {
        guard FeatureFlagService.shared.isEnabled(.googleTasks) else { return }
        guard isConnected, !isSyncing else { return }
        // However often a pass is asked for, it starts at most once per floor. See SyncPassFloor.
        guard SyncPassFloor.mayStart(lastPassStarted: lastPassStarted, now: Date(),
                                     floor: SyncPassFloor.defaultFloor) else {
            rerunAfterPass = true
            scheduleSync()
            return
        }
        lastPassStarted = Date()
        isSyncing = true
        lastError = nil
        defer {
            isSyncing = false
            if rerunAfterPass { rerunAfterPass = false; scheduleSync() }
        }
        // The pass is the core's (AITD-463): auto-link, every linked list, then My Tasks against
        // Google's default list. One list failing is reported without stopping the others.
        // The first launch after the move imports the Swift ledger; a pass before it lands could
        // miss a queued deletion or bring a deleted task back.
        await GoogleLedgerUpgrade.finished()
        do {
            let report = try await core.run(CoreCommand(kind: "syncExternal"), as: CorePassReport.self)
            lastError = report.firstError
        } catch {
            lastError = error.localizedDescription
        }
        lastSyncedAt = Date()
        // Auto-link may have made links; the settings screens draw from `links`.
        await refreshStatus()
    }
}

/// What the core's `syncExternal` answers, read only for the first failure to show.
private struct CorePassReport: Decodable {
    struct Pass: Decodable { let linkId: String; let error: String? }
    let passes: [Pass]

    var firstError: String? { passes.lazy.compactMap(\.error).first }
}

/// Google Tasks sync mode: how lists get linked. Stored server-side in
/// Integration.metadata (`googleSyncMode` / `listSuffix`) so the choice
/// follows the account across devices.
enum GoogleSyncMode: String, CaseIterable {
    /// Link lists one at a time (list settings / Settings → Google Tasks).
    case manual
    /// Every Google tasklist mirrors into Astrid; new tasklists are picked up
    /// on each sync and get an Astrid list (with an optional name suffix).
    case allGoogleToAstrid = "all_google_to_astrid"
    /// Every Astrid list mirrors out to Google Tasks (backup); new Astrid
    /// lists are picked up on each sync and get a Google tasklist.
    case allAstridToGoogle = "all_astrid_to_google"
    /// Both directions: every Google tasklist mirrors in AND every Astrid
    /// list mirrors out — same-name pairs adopt each other, never duplicate.
    case allBidirectional = "all_bidirectional"
}
