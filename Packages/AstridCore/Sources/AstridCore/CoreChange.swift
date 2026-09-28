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
        case "notifications": self = .notifications
        case "stream": self = .stream(live: wire.live ?? false)
        default: self = .unknown(json)
        }
    }
}
