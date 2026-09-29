//  CoreUpgrade.swift
//  The first launch after the data layer moved into astrid-core: nothing the Swift layer held may
//  be lost on the way.
//
//  Two things carry over, once:
//
//  - **What the cache showed.** Core Data's tasks, lists, comments, boards and chat seed the
//    core's cache, so a launch with no network still shows everything. The first sync pass
//    replaces the seed with the server's answer.
//  - **What had not been sent.** Writes still waiting in the Swift Outbox (`outbox.json`) —
//    tasks, lists, comments, chat, and the uploads a comment or message waits on — move into the
//    core's journal, task and list edits verbatim under their original idempotency keys, so an
//    edit made offline before the update still reaches the server and one the old journal did
//    send is not made twice.

import AstridCore
import CoreData
import Foundation

@MainActor
enum CoreUpgrade {
    static let doneKey = "core.upgrade.v1"

    /// Carry the Swift layer's cache and unsent writes into the core — once it has all gone.
    ///
    /// Marked done only when the seed was taken and no queued write was left behind: a launch
    /// that could not move something tries again next time (the core imports each write once, and
    /// seeds only an empty cache), rather than leaving it in `outbox.json` for good.
    static func runIfNeeded(_ session: CoreSession) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let seeded = seed(session)
        let leftBehind = importJournal(session)
        if seeded && leftBehind == 0 {
            UserDefaults.standard.set(true, forKey: doneKey)
        } else {
            AppLog.debug("⚠️ [CoreUpgrade] Not finished (seeded: \(seeded), left behind: \(leftBehind)); trying again next launch")
        }
    }

    // MARK: - The cache

    /// Whether the seed was taken — or there was nothing to seed, or the cache already had it.
    @discardableResult
    private static func seed(_ session: CoreSession) -> Bool {
        let context = CoreDataManager.shared.viewContext
        let lists = ((try? CDTaskList.fetchAll(context: context)) ?? []).map { $0.toDomainModel() }
        let taskRows = (try? context.fetch(CDTask.fetchRequest())) ?? []
        let tasks = taskRows.filter { $0.syncStatus != "pending_delete" }.map { $0.toDomainModel() }
        let commentRows = (try? context.fetch(CDComment.fetchRequest())) ?? []
        let comments = commentRows
            .filter { !$0.id.isEmpty && $0.syncStatus != "pending_delete" }
            .map { $0.toDomainModel() }
        guard !tasks.isEmpty || !lists.isEmpty else { return true }
        let projects = ((try? CDProject.fetchAll(context: context)) ?? []).map { $0.toDomainModel() }
        let channels = ((try? CDChatChannel.fetchAll(context: context)) ?? []).map { $0.toDomainModel() }
        let messages = ((try? context.fetch(CDChatMessage.fetchRequest())) ?? [])
            .filter { !$0.id.isEmpty && $0.syncStatus != "pending_delete" }
            .map { $0.toDomainModel() }
        var command = CoreCommand(kind: "seedCache")
        command.set("tasks", tasks)
        command.set("lists", lists)
        command.set("comments", comments)
        command.set("projects", projects)
        command.set("channels", channels)
        command.set("messages", messages)
        struct Seeded: Decodable { let seeded: Bool }
        let seeded = try? session.runBlocking(command, as: Seeded.self)
        AppLog.debug("📦 [CoreUpgrade] Seeded the core's cache from Core Data: \(seeded?.seeded ?? false) (\(tasks.count) tasks, \(lists.count) lists)")
        return seeded != nil
    }

    // MARK: - The journal

    /// The kinds that move — every kind the Swift Outbox had. An upload moves with the comment or
    /// message that waits on it: the core uploads and sends in one go.
    static let movedKinds: Set<String> = [
        "createTask", "updateTask", "deleteTask", "updateList",
        "createComment", "updateComment", "deleteComment", "sendChatMessage",
    ]

    /// Move the Swift Outbox's queued writes; answers how many had to be left behind.
    @discardableResult
    private static func importJournal(_ session: CoreSession) -> Int {
        let store = OutboxStore(fileURL: OutboxStore.defaultFileURL())
        let entries = store.load()
        var kept: [OutboxEntry] = []
        var moved = 0
        let byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // An upload a moved comment waits on moves with it: the core uploads and posts in one go.
        var consumedUploads = Set<String>()
        for entry in entries {
            guard movedKinds.contains(entry.kind), entry.status == .pending || entry.status == .running,
                  let command = importCommand(for: entry, uploads: byId) else {
                if !movedKinds.contains(entry.kind) { kept.append(entry) }
                continue
            }
            if entry.kind == "createComment" || entry.kind == "sendChatMessage" {
                consumedUploads.formUnion(entry.dependsOn.filter { byId[$0]?.kind == "uploadAttachment" })
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
        kept = leftBehind(kept, consumedUploads: consumedUploads)
        moved += importOfflineLists(session)
        moved += importQueuedMemberChanges(session)
        if kept.isEmpty {
            try? FileManager.default.removeItem(at: OutboxStore.defaultFileURL())
        } else if moved > 0 {
            try? store.save(kept)
        }
        AppLog.debug("📦 [CoreUpgrade] Moved \(moved) queued writes into the core's journal, \(kept.count) left behind")
        return kept.count
    }

    /// What stays in `outbox.json` once the moved writes are gone: not an upload a moved write took
    /// with it, and not an upload no write that stayed still waits on — alone it has nothing to
    /// attach to, and would keep the upgrade from ever finishing.
    static func leftBehind(_ kept: [OutboxEntry], consumedUploads: Set<String>) -> [OutboxEntry] {
        let remaining = kept.filter { !consumedUploads.contains($0.id) }
        let stillNeeded = Set(remaining.flatMap(\.dependsOn))
        return remaining.filter { $0.kind != "uploadAttachment" || stillNeeded.contains($0.id) }
    }

    /// The core's journal entry for one of the Swift Outbox's, in the core's payload shape.
    static func importCommand(for entry: OutboxEntry, uploads: [String: OutboxEntry] = [:]) -> CoreCommand? {
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
        case "createComment":
            guard let create = try? decoder.decode(CreateCommentOutboxPayload.self, from: entry.payload) else { return nil }
            // A photo still to upload: the core copies it, uploads it and posts the comment.
            if let fileId = create.fileId, fileId.hasPrefix("temp_"),
               let upload = entry.dependsOn.compactMap({ uploads[$0] }).first(where: { $0.kind == "uploadAttachment" }),
               let staged = try? decoder.decode(UploadAttachmentOutboxPayload.self, from: upload.payload) {
                var attach = CoreCommand(kind: "attachFile", [
                    "taskId": .value(create.taskId), "path": .value(staged.localPath),
                    "content": .value(create.content), "fileId": .value(fileId),
                    "name": .value(staged.fileName), "mimeType": .value(staged.mimeType),
                    "clientRequestId": .value(entry.clientRequestId),
                ])
                attach.set("parentCommentId", create.parentCommentId)
                return attach
            }
            var post = CoreCommand(kind: "postComment", [
                "taskId": .value(create.taskId), "content": .value(create.content),
                "clientRequestId": .value(entry.clientRequestId),
            ])
            post.set("type", create.type)
            post.set("parentCommentId", create.parentCommentId)
            post.set("fileId", create.fileId)
            return post
        case "sendChatMessage":
            guard let send = try? decoder.decode(SendChatMessageOutboxPayload.self, from: entry.payload) else { return nil }
            var command = CoreCommand(kind: "sendChatMessage", [
                "channelId": .value(send.channelId), "content": .value(send.content),
                "type": .value(send.type),
            ])
            command.set("replyToId", send.replyToId)
            command.set("fileId", send.fileId)
            // A picture still to upload: the core copies it, uploads it and sends the message.
            if let fileId = send.fileId, fileId.hasPrefix("temp_"),
               let upload = entry.dependsOn.compactMap({ uploads[$0] }).first(where: { $0.kind == "uploadAttachment" }),
               let staged = try? decoder.decode(UploadAttachmentOutboxPayload.self, from: upload.payload) {
                command.set("path", staged.localPath)
                command.set("name", staged.fileName)
                command.set("mimeType", staged.mimeType)
            }
            return command
        case "updateComment":
            guard let update = try? decoder.decode(UpdateCommentOutboxPayload.self, from: entry.payload) else { return nil }
            payload = CoreFields(fields: [
                "commentId": .value(update.commentId),
                "body": .value(CoreFields(fields: ["content": .value(update.content)])),
            ])
            tempId = update.commentId.hasPrefix("temp_") ? update.commentId : nil
        case "deleteComment":
            guard let delete = try? decoder.decode(DeleteCommentOutboxPayload.self, from: entry.payload) else { return nil }
            payload = CoreFields(fields: ["commentId": .value(delete.commentId)])
            tempId = delete.commentId.hasPrefix("temp_") ? delete.commentId : nil
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

    /// Membership changes made offline waited in Core Data (`CDMember`), not the Swift Outbox.
    /// They move into the core's journal in its own shapes (CONTRACTS D31).
    private static func importQueuedMemberChanges(_ session: CoreSession) -> Int {
        let context = CoreDataManager.shared.viewContext
        let queued = ((try? CDMember.fetchAll(context: context)) ?? [])
            .filter { $0.syncStatus != "synced" && $0.syncStatus != "failed" }
        var moved = 0
        for member in queued {
            let listId = CoreValue.value(member.listId)
            let payload: CoreFields
            let kind: String
            switch member.pendingOperation {
            case "create":
                // The address typed was kept in `pendingRole` — the old queue's one spare column.
                guard let email = member.pendingRole else { continue }
                kind = "inviteToList"
                payload = CoreFields(fields: ["listId": listId, "body": .object([
                    "email": .value(email), "role": .value(member.role),
                ])])
            case "update":
                guard let role = member.pendingRole else { continue }
                kind = "setMemberRole"
                payload = CoreFields(fields: ["listId": listId, "userId": .value(member.id),
                                              "body": .object(["role": .value(role)])])
            case "delete":
                kind = "removeMember"
                payload = CoreFields(fields: ["listId": listId, "userId": .value(member.id)])
            default:
                continue
            }
            // Keyed by the row and the change, so an upgrade that runs again imports it once.
            let command = journalCommand(kind: kind, payload: payload,
                                         clientRequestId: "cdmember-\(member.listId)-\(member.id)-\(kind)",
                                         tempId: nil)
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

// MARK: - The Swift Outbox's payloads
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

nonisolated struct CreateCommentOutboxPayload: Codable, Equatable {
    var taskId: String
    var content: String
    var type: String
    var parentCommentId: String?
    var createdAt: Date?
    /// Attachment file id at enqueue time — may be a temp id resolved at run time
    /// from the (legacy) upload, or nil for a plain comment.
    var fileId: String?
}

nonisolated struct UpdateCommentOutboxPayload: Codable, Equatable {
    var commentId: String
    var content: String
}

nonisolated struct DeleteCommentOutboxPayload: Codable, Equatable {
    var commentId: String
}

/// A queued `uploadAttachment`: the bytes stay on disk at `localPath`.
nonisolated struct UploadAttachmentOutboxPayload: Codable, Equatable {
    var localPath: String
    var fileName: String
    var mimeType: String
    var context: [String: String]   // e.g. {"taskId": "..."} or {"channelId": "..."}
}

/// A queued `sendChatMessage`. `fileId` may be a temp id its upload was to resolve.
nonisolated struct SendChatMessageOutboxPayload: Codable, Equatable {
    var channelId: String
    var content: String
    var type: String
    var fileId: String?
    var replyToId: String?
}
