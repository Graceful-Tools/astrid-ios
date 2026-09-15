import Foundation

/// Self-contained payload for an `updateList` Outbox entry (AITD-410).
///
/// `ListService.updateListAdvanced` takes `[String: Any]` rather than a typed request, because
/// clearing a field has to be distinguishable from leaving it alone: `ListSettingsPayload` sends
/// `NSNull()` for "clear this" and omits the key entirely for "don't touch". A `Codable` struct
/// of optionals cannot express that difference, so the dictionary is journaled as its JSON text
/// and replayed verbatim. `NSNull` round-trips through `JSONSerialization` as `null`, which is
/// exactly the byte the server needs to see.
///
/// The JSON is held as a `String` rather than `Data` so the journal on disk — and the
/// Settings → Outbox readout — stays human-readable instead of base64.
nonisolated struct UpdateListOutboxPayload: Codable, Equatable {
    var listId: String
    var updatesJSON: String

    /// nil when the dictionary isn't JSON-serializable, which would otherwise journal an entry
    /// that can never be decoded and would dead-letter on its first run.
    init?(listId: String, updates: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(updates),
              let data = try? JSONSerialization.data(withJSONObject: updates),
              let text = String(data: data, encoding: .utf8) else { return nil }
        self.listId = listId
        self.updatesJSON = text
    }

    /// The dictionary this payload was built from, ready to hand back to the API client.
    var updates: [String: Any]? {
        guard let data = updatesJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}

extension UpdateListOutboxPayload {
    /// Journal a list update that failed against the server, so it is replayed on reconnect
    /// instead of being dropped (AITD-410). Lives here rather than in `ListService` because it
    /// needs none of the service's state — only the two values the failed call already had.
    ///
    /// A body that will not serialize is reported rather than journaled: an entry that cannot be
    /// decoded can only dead-letter on its first run, so claiming it is queued would be a second
    /// version of the lie this task exists to remove.
    static func enqueueReplay(listId: String, updates: [String: Any]) async {
        guard let payload = UpdateListOutboxPayload(listId: listId, updates: updates) else {
            AppLog.debug("❌ [ListService] List update could NOT be queued (unserializable): \(updates)")
            return
        }
        await OutboxManager.shared.enqueueUpdateList(payload, clientRequestId: UUID().uuidString)
        AppLog.debug("📥 [ListService] Queued list update for replay on reconnect")
    }
}

/// Outbox handler for a list update. PUT is value-idempotent and iOS doesn't send
/// `If-Unmodified-Since`, so replaying the same body is safe — including the case where the
/// original request reached the server but its response was lost.
enum UpdateListOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(UpdateListOutboxPayload.self, from: entry.payload) else {
            return .permanent("updateList: undecodable payload")
        }
        guard let updates = payload.updates else {
            return .permanent("updateList: undecodable updates")
        }

        // A list created offline has no server id yet. Its create is replayed by
        // `ListService.syncPendingLists`, which swaps the temp id for the real one and reports
        // it through `onListSynced`; until that lands there is nothing to PUT to, so wait
        // rather than burn an attempt on a guaranteed 404.
        var listId = payload.listId
        if listId.hasPrefix("temp_") {
            guard let real = await TaskService.shared.mappedRealListId(for: listId) else {
                return .blocked("updateList: list not yet synced")
            }
            listId = real
        }

        do {
            let updated = try await AstridAPIClient.shared.updateListWithDictionary(
                id: listId, updates: updates)
            await ListService.shared.reconcileOutboxUpdatedList(updated)
            return .success([:])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}
