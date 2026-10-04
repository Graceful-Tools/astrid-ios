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
    static let doneKey = "core.upgrade.googleLedger.v1"

    /// Import once. Marked done only when the core says the import worked, so a launch that could
    /// not import tries again next time. The import is idempotent.
    static func runIfNeeded(_ session: CoreSession, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        do {
            try session.runBlocking(command(defaults: defaults), as: Imported.self)
            defaults.set(true, forKey: doneKey)
        } catch {
            AppLog.debug("⚠️ [GoogleLedgerUpgrade] Import failed (\(error)); trying again next launch")
        }
    }

    private struct Imported: Decodable {}

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
