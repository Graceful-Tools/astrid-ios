import Foundation

/// What a new task starts out as before anybody changes it — astrid-core's `quickAddDefaults`
/// rule (core `317e546`, AITD-646): the list's defaults filling only the gaps the person left.
///
/// Synchronous and pure, so a quick-add control can ask from a view body as it draws.

/// The list a new task is going into, as the wire carries it: the fields the rule reads.
public struct QuickAddList: Encodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let defaultPriority: Int?
    public let defaultRepeating: String?
    /// `nil` is the task's creator, `"unassigned"` is nobody, anything else is that user.
    public let defaultAssigneeId: String?
    /// `today`, `tomorrow`, `next_week`, `next_month`, or `none`.
    public let defaultDueDate: String?
    /// `HH:mm`, or `nil` for all day.
    public let defaultDueTime: String?
    public let defaultIsPrivate: Bool?

    public init(id: String, name: String, defaultPriority: Int? = nil, defaultRepeating: String? = nil,
                defaultAssigneeId: String? = nil, defaultDueDate: String? = nil,
                defaultDueTime: String? = nil, defaultIsPrivate: Bool? = nil) {
        self.id = id
        self.name = name
        self.defaultPriority = defaultPriority
        self.defaultRepeating = defaultRepeating
        self.defaultAssigneeId = defaultAssigneeId
        self.defaultDueDate = defaultDueDate
        self.defaultDueTime = defaultDueTime
        self.defaultIsPrivate = defaultIsPrivate
    }
}

/// The fields `createTask` would send. Every one is present, including the empty answers.
public struct QuickAddDefaults: Decodable, Equatable, Sendable {
    /// 0 (none) through 3 (urgent).
    public let priority: Int
    public let assigneeId: String?
    /// For an all-day task, the day at UTC midnight — the way every all-day date is stored.
    public let dueDateTime: Date?
    public let isAllDay: Bool
    /// `daily`, `weekly`, `monthly` or `yearly`; `nil` for none.
    public let repeating: String?
    public let isPrivate: Bool

    public init(priority: Int, assigneeId: String?, dueDateTime: Date?, isAllDay: Bool,
                repeating: String?, isPrivate: Bool) {
        self.priority = priority
        self.assigneeId = assigneeId
        self.dueDateTime = dueDateTime
        self.isAllDay = isAllDay
        self.repeating = repeating
        self.isPrivate = isPrivate
    }
}

extension CoreRules {
    /// A new task's defaults in `list` — `nil` for My Tasks and the other synthesised views, which
    /// have none, though the creator is still the fallback assignee there.
    ///
    /// `priority` and `assigneeId` are what the person already picked: sending one is what makes
    /// that field said, and a default never overrides it. `"unassigned"` is a choice of nobody.
    /// `userId` is the signed-in user, `nil` when signed out.
    public static func quickAddDefaults(
        list: QuickAddList?, userId: String?, now: Date = Date(), timeZone: TimeZone = .current,
        priority: Int? = nil, assigneeId: String? = nil
    ) throws -> QuickAddDefaults {
        try ask(QuickAddDefaultsRequest(list: list, userId: userId, now: now,
                                        utcOffsetMinutes: timeZone.secondsFromGMT(for: now) / 60,
                                        priority: priority, assigneeId: assigneeId),
                as: QuickAddDefaults.self)
    }
}

private struct QuickAddDefaultsRequest: Encodable {
    let kind = "quickAddDefaults"
    let list: QuickAddList?
    let userId: String?
    let now: Date
    let utcOffsetMinutes: Int
    let priority: Int?
    let assigneeId: String?
}
