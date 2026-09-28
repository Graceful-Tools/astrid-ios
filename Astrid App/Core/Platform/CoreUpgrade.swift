//  CoreUpgrade.swift
//  The first launch after the data layer moved into astrid-core: nothing the Swift layer held may
//  be lost on the way.
//
//  Two things carry over, once:
//
//  - **What the cache showed.** Core Data's tasks and lists seed the core's cache, so a launch
//    with no network still shows everything. The first sync pass replaces the seed with the
//    server's answer.
//  - **What had not been sent.** Task and list writes still waiting in the Swift Outbox
//    (`outbox.json`) move into the core's journal verbatim, under their original idempotency keys,
//    so an edit made offline before the update still reaches the server — and one the old journal
//    did send is not made twice.

import AstridCore
import CoreData
import Foundation

@MainActor
enum CoreUpgrade {
    static let doneKey = "core.upgrade.v1"

    /// Carry the Swift layer's cache and unsent writes into the core, the first time only.
    static func runIfNeeded(_ session: CoreSession) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        seed(session)
        importJournal(session)
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    // MARK: - The cache

    private static func seed(_ session: CoreSession) {
        let context = CoreDataManager.shared.viewContext
        let lists = ((try? CDTaskList.fetchAll(context: context)) ?? []).map { $0.toDomainModel() }
        let taskRows = (try? context.fetch(CDTask.fetchRequest())) ?? []
        let tasks = taskRows.filter { $0.syncStatus != "pending_delete" }.map { $0.toDomainModel() }
        guard !tasks.isEmpty || !lists.isEmpty else { return }
        var command = CoreCommand(kind: "seedCache")
        command.set("tasks", tasks)
        command.set("lists", lists)
        struct Seeded: Decodable { let seeded: Bool }
        let seeded = try? session.runBlocking(command, as: Seeded.self)
        AppLog.debug("📦 [CoreUpgrade] Seeded the core's cache from Core Data: \(seeded?.seeded ?? false) (\(tasks.count) tasks, \(lists.count) lists)")
    }

    // MARK: - The journal

    /// The kinds that move: the ones the core now owns. Comment, chat and attachment writes stay in
    /// the Swift Outbox until their services move too.
    static let movedKinds: Set<String> = ["createTask", "updateTask", "deleteTask", "updateList"]

    private static func importJournal(_ session: CoreSession) {
        let store = OutboxStore(fileURL: OutboxStore.defaultFileURL())
        let entries = store.load()
        var kept: [OutboxEntry] = []
        var moved = 0
        for entry in entries {
            guard movedKinds.contains(entry.kind), entry.status == .pending || entry.status == .running,
                  let command = importCommand(for: entry) else {
                if !movedKinds.contains(entry.kind) { kept.append(entry) }
                continue
            }
            do {
                try session.runBlocking(command, as: JSONValue.self)
                moved += 1
            } catch {
                // A write the core would not take is kept where it was, not dropped.
                AppLog.debug("⚠️ [CoreUpgrade] Could not move \(entry.kind) \(entry.id): \(error)")
                kept.append(entry)
            }
        }
        // Pending lists created offline never reached the Swift Outbox — ListService re-sent them
        // from Core Data. Their create moves into the core's journal the same way.
        moved += importOfflineLists(session)
        if moved > 0 { try? store.save(kept) }
        AppLog.debug("📦 [CoreUpgrade] Moved \(moved) queued writes into the core's journal")
    }

    /// The core's journal entry for one of the Swift Outbox's, in the core's payload shape.
    static func importCommand(for entry: OutboxEntry) -> CoreCommand? {
        let decoder = JSONDecoder()
        var payload: CoreFields
        var tempId: String?
        switch entry.kind {
        case "createTask":
            guard let create = try? decoder.decode(CreateTaskOutboxPayload.self, from: entry.payload) else { return nil }
            var body = CoreFields()
            body.set("title", create.title)
            body.set("listIds", create.listIds)
            body.set("description", create.description)
            body.set("priority", create.priority)
            body.set("assigneeId", create.assigneeId)
            body.set("dueDateTime", create.dueDateTime.map(WireDate.dueDateString(from:)))
            body.set("isAllDay", create.isAllDay)
            body.set("isPrivate", create.isPrivate)
            body.set("repeating", create.repeating)
            body.set("repeatingData", create.repeatingData)
            body.set("parentTaskId", create.parentTaskId)
            body.set("statusRole", create.statusRole)
            payload = CoreFields(fields: ["body": .value(body)])
            tempId = create.tempId
        case "updateTask":
            guard let update = try? decoder.decode(UpdateTaskOutboxPayload.self, from: entry.payload),
                  let body = try? JSONValue(encoding: update.updates) else { return nil }
            payload = CoreFields(fields: ["taskId": .value(update.taskId), "body": .value(body)])
            tempId = update.taskId.hasPrefix("temp_") ? update.taskId : nil
        case "deleteTask":
            guard let delete = try? decoder.decode(DeleteTaskOutboxPayload.self, from: entry.payload) else { return nil }
            payload = CoreFields(fields: ["taskId": .value(delete.taskId)])
            tempId = delete.taskId.hasPrefix("temp_") ? delete.taskId : nil
        case "updateList":
            guard let update = try? decoder.decode(UpdateListOutboxPayload.self, from: entry.payload),
                  let data = update.updatesJSON.data(using: .utf8),
                  let body = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
            payload = CoreFields(fields: ["listId": .value(update.listId), "body": .value(body)])
            tempId = update.listId.hasPrefix("temp_") ? update.listId : nil
        default:
            return nil
        }
        return journalCommand(kind: entry.kind, payload: payload,
                              clientRequestId: entry.clientRequestId, tempId: tempId)
    }

    private static func importOfflineLists(_ session: CoreSession) -> Int {
        let context = CoreDataManager.shared.viewContext
        let pending = ((try? CDTaskList.fetchAll(context: context)) ?? [])
            .filter { $0.id.hasPrefix("temp_") && ListSyncStatus.unsynced.contains($0.syncStatus) }
            .map { $0.toDomainModel() }
        var moved = 0
        for list in pending {
            var body = CoreFields()
            body.set("name", list.name)
            body.set("color", list.color)
            body.set("privacy", list.privacy?.rawValue)
            body.set("description", list.description)
            let command = journalCommand(
                kind: "createList", payload: CoreFields(fields: ["body": .value(body)]),
                clientRequestId: list.id, tempId: list.id)
            if (try? session.runBlocking(command, as: JSONValue.self)) != nil { moved += 1 }
        }
        return moved
    }

    private static func journalCommand(
        kind: String, payload: CoreFields, clientRequestId: String, tempId: String?
    ) -> CoreCommand {
        var command = CoreCommand(kind: "importJournalEntry", [
            "entryKind": .value(kind),
            "payload": .value(payload),
            "clientRequestId": .value(clientRequestId),
        ])
        command.set("tempId", tempId)
        return command
    }
}

// MARK: - The Swift Outbox's task and list payloads
//
// Kept only to read the entries a pre-core build left in `outbox.json`. Nothing writes them now.

/// A queued `createTask`, as the Swift Outbox journaled it.
nonisolated struct CreateTaskOutboxPayload: Codable, Equatable {
    var title: String
    var listIds: [String]?
    var description: String?
    var priority: Int?
    var assigneeId: String?
    var dueDateTime: Date?
    var isAllDay: Bool?
    var isPrivate: Bool?
    var repeating: String?
    var repeatingData: CustomRepeatingPattern?
    var tempId: String?
    var parentTaskId: String?
    var statusRole: String?
    var source: String?
}

/// A queued `updateTask`, as the Swift Outbox journaled it.
nonisolated struct UpdateTaskOutboxPayload: Codable {
    var taskId: String
    var updates: UpdateTaskRequest
    var source: String?
}

/// A queued `deleteTask`, as the Swift Outbox journaled it.
nonisolated struct DeleteTaskOutboxPayload: Codable, Equatable {
    var taskId: String
}

/// A queued `updateList`, as the Swift Outbox journaled it: the settings dictionary as JSON text,
/// so a cleared field (`null`) survives the trip.
nonisolated struct UpdateListOutboxPayload: Codable, Equatable {
    var listId: String
    var updatesJSON: String
}
