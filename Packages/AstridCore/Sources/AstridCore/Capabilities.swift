import Foundation

/// The editing controls a task's lists let an editor offer, and what deleting it is called —
/// astrid-core's `capabilities` rule (`capabilities::for_lists`, AITD-667).
///
/// Only a loaded list the task is on can refuse a control: a list not loaded yet refuses
/// nothing, because hiding a control that works is the worse mistake. Deleting is a removal only
/// when some list removes and none deletes (a task also on a classic list really is deleted).
public struct ListCapabilities: Decodable, Equatable, Sendable {
    public enum Deletion: String, Decodable, Sendable {
        case delete, removeFromList
    }

    public let priority: Bool
    public let dueDate: Bool
    public let privateTasks: Bool
    public let deletion: Deletion

    /// A classic list: everything allowed, and a delete deletes.
    public static let classic = ListCapabilities(priority: true, dueDate: true, privateTasks: true,
                                                 deletion: .delete)

    public init(priority: Bool, dueDate: Bool, privateTasks: Bool, deletion: Deletion) {
        self.priority = priority; self.dueDate = dueDate
        self.privateTasks = privateTasks; self.deletion = deletion
    }
}

extension CoreRules {
    /// What a task on `listIds` may offer, judged by `lists` (their wire shape). Never throws: a
    /// question the core cannot read answers `.classic`, the safe direction — the server refuses
    /// a write it cannot take, while a hidden control is a feature nobody finds.
    public static func capabilities(listIds: [String], lists: some Encodable) -> ListCapabilities {
        (try? ask(CapabilitiesRequest(listIds: listIds, lists: AnyEncodable(lists)),
                  as: ListCapabilities.self)) ?? .classic
    }
}

private struct CapabilitiesRequest: Encodable {
    let kind = "capabilities"
    let listIds: [String]
    let lists: AnyEncodable
}
