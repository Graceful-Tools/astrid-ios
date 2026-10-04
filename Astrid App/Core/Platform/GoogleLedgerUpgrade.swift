//  GoogleLedgerUpgrade.swift
//  The first launch after the Google pass moved into astrid-core (AITD-463): the deletion ledger the
//  Swift pass kept in UserDefaults moves into the core's, once.
//
//  What carries over:
//
//  - **Pending deletions** — the Google twins of tasks deleted here that the Swift pass had not yet
//    removed. Without them a task deleted just before the update would stay in Google.
//  - **Tombstones**, this device's and the server's, so a pull never brings a deleted task back.
//  - **The task → twin cache**, so deleting a task the core has not fetched links for yet still
//    finds its twin. The server cascades the link row away with the task, so the core has only
//    its own remembered links to go on.

import AstridCore
import Foundation

@MainActor
enum GoogleLedgerUpgrade {
    /// Cleared at sign-out with the other per-user sync keys (`SyncStateReset`).
    nonisolated static let doneKey = "core.upgrade.googleLedger.v1"

    /// The launch's import, for a Google pass to wait on.
    private static var inFlight: _Concurrency.Task<Void, Never>?

    /// Start the import at launch. Awaited, not `runBlocking`: the core refuses a command that may
    /// reach the network on the blocking path, and this one is not on its local-only list.
    static func start(_ session: CoreSession) {
        inFlight = _Concurrency.Task { await runIfNeeded(session) }
    }

    /// What a Google pass waits for first, so no pass reads a ledger the import has not reached.
    static func finished() async {
        await inFlight?.value
    }

    /// Import once. Marked done only when the core says the import worked, so a launch that could
    /// not import tries again next time. The import is idempotent.
    static func runIfNeeded(_ session: CoreSession, defaults: UserDefaults = .standard) async {
        await runIfNeeded(defaults: defaults) { try await session.run($0) }
    }

    /// The Swift pass's stores this import reads. Removed once the core holds them: the core merges
    /// an import, so a stale copy imported a second time would put back links and deletions it has
    /// since moved past.
    static let swiftKeys = SyncDeletionLedger(provider: "google").storageKeys + ["googleTaskLinkCache"]

    static func runIfNeeded(defaults: UserDefaults = .standard,
                            run: (CoreCommand) async throws -> Void) async {
        guard !defaults.bool(forKey: doneKey) else { return }
        do {
            try await run(command(defaults: defaults))
            defaults.set(true, forKey: doneKey)
            for key in swiftKeys { defaults.removeObject(forKey: key) }
        } catch {
            AppLog.debug("⚠️ [GoogleLedgerUpgrade] Import failed (\(error)); trying again next launch")
        }
    }

    nonisolated struct Pending: Encodable, Equatable, Sendable { let remoteId: String; let containerId: String }
    nonisolated struct Link: Encodable, Equatable, Sendable { let taskId: String; let remoteId: String; let containerId: String }

    /// The import, read from the Swift stores. Oldest first, as the stores keep them, so the core's
    /// caps evict the same entries the Swift ones would have.
    static func command(defaults: UserDefaults) -> CoreCommand {
        // SyncDeletionLedger(provider: "google")'s keys.
        let pendingMap = defaults.dictionary(forKey: "syncPendingRemoteDeletes.google") as? [String: String] ?? [:]
        let pending = pendingMap.sorted { $0.key < $1.key }
            .map { Pending(remoteId: $0.key, containerId: $0.value) }
        let tombstones = defaults.stringArray(forKey: "syncDeletedRemoteIds.google") ?? []
        let serverTombstones = defaults.stringArray(forKey: "syncServerTombstones.google") ?? []
        let cached = defaults.dictionary(forKey: "googleTaskLinkCache") as? [String: String] ?? [:]
        let links: [Link] = cached.sorted { $0.key < $1.key }.compactMap { taskId, value in
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return Link(taskId: taskId, remoteId: parts[0], containerId: parts[1])
        }
        var command = CoreCommand(kind: "importExternalLedger")
        command.set("provider", "google_tasks")
        command.set("pending", pending)
        command.set("tombstones", tombstones)
        command.set("serverTombstones", serverTombstones)
        command.set("links", links)
        return command
    }
}
