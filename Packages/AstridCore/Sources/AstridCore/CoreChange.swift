import Foundation

/// What moved in the core's cache — `astrid_core::realtime::Change`, as `Change::to_json` spells it.
public enum CoreChange: Equatable, Sendable {
    case task(id: String)
    case list(id: String)
    case comments(taskId: String)
    case chat(channelId: String)
    /// An agent starting or stopping a reply, in a list's chat (`channelId`) or on a task's
    /// comments (`taskId`); `agentName` is what the indicator says.
    case agentTyping(channelId: String?, taskId: String?, agentName: String?, active: Bool)
    case settings
    case remindersDue
    /// Something the live stream could not describe changed: ask for a sync pass.
    case needsSync
    /// A pass nobody asked for brought these into the cache. Both empty means it could not say
    /// which, and whatever is on screen should be read again.
    case synced(taskIds: [String], listIds: [String])
    /// The Outbox settled some writes — delivered, or refused for good — and these are what they
    /// touched, with the journal's counts (AITD-454).
    case delivered(CoreDelivery)
    case notifications
    /// The live stream connected (`true`) or dropped.
    case stream(live: Bool)
    /// A change this build does not know — a newer core. Treated as "read everything again".
    case unknown(String)

    /// Read one `{"change":…}` object. Never fails: something unreadable is `unknown`.
    public init(json: String) {
        struct Wire: Decodable {
            let change: String
            let id: String?
            let taskId: String?
            let channelId: String?
            let active: Bool?
            let agentName: String?
            let taskIds: [String]?
            let listIds: [String]?
            let live: Bool?
            let commentTaskIds: [String]?
            let channelIds: [String]?
            let undescribed: Bool?
            let pending: Int?
            let running: Int?
            let failed: Int?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else {
            self = .unknown(json)
            return
        }
        switch wire.change {
        case "task": self = wire.id.map { .task(id: $0) } ?? .unknown(json)
        case "list": self = wire.id.map { .list(id: $0) } ?? .unknown(json)
        case "comments": self = wire.taskId.map { .comments(taskId: $0) } ?? .unknown(json)
        case "chat": self = wire.channelId.map { .chat(channelId: $0) } ?? .unknown(json)
        case "agentTyping" where wire.channelId != nil || wire.taskId != nil:
            self = .agentTyping(channelId: wire.channelId, taskId: wire.taskId,
                                agentName: wire.agentName, active: wire.active ?? false)
        case "settings": self = .settings
        case "remindersDue": self = .remindersDue
        case "needsSync": self = .needsSync
        case "synced": self = .synced(taskIds: wire.taskIds ?? [], listIds: wire.listIds ?? [])
        case "delivered":
            self = .delivered(CoreDelivery(
                taskIds: wire.taskIds ?? [], listIds: wire.listIds ?? [],
                commentTaskIds: wire.commentTaskIds ?? [], channelIds: wire.channelIds ?? [],
                // A delivery that names nothing it touched and does not say it touched nothing
                // came from a core this build does not understand: read everything again.
                undescribed: wire.undescribed ?? true,
                pending: wire.pending ?? 0, running: wire.running ?? 0, failed: wire.failed ?? 0))
        case "notifications": self = .notifications
        case "stream": self = .stream(live: wire.live ?? false)
        default: self = .unknown(json)
        }
    }
}

/// What one Outbox drain settled (`astrid_core::outbox::Delivery`), and the journal's counts after it.
public struct CoreDelivery: Equatable, Sendable {
    /// Tasks written, temporary and real ids both for a create.
    public var taskIds: [String]
    public var listIds: [String]
    /// Tasks whose comment threads moved.
    public var commentTaskIds: [String]
    public var channelIds: [String]
    /// Something settled that the core could not describe: refresh everything shown.
    public var undescribed: Bool
    public var pending: Int
    public var running: Int
    public var failed: Int

    public init(taskIds: [String], listIds: [String], commentTaskIds: [String], channelIds: [String],
                undescribed: Bool, pending: Int, running: Int, failed: Int) {
        self.taskIds = taskIds
        self.listIds = listIds
        self.commentTaskIds = commentTaskIds
        self.channelIds = channelIds
        self.undescribed = undescribed
        self.pending = pending
        self.running = running
        self.failed = failed
    }
}
