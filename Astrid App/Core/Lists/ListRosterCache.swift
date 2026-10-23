import Foundation

/// The people a cached list knows about, kept so an OFFLINE COLD LAUNCH can still name them
/// (AITD-413 — "Cannot assign tasks when offline").
///
/// `CDTaskList` persisted a list's settings, filters and board role but not its `owner` or its
/// `listMembers`, so a list rehydrated from CoreData came back knowing nobody. Online that never
/// showed: `fetchLists()` re-hydrated the in-memory copy within a second. Offline it is the only
/// copy there is, and the assignee picker (the core's `assigneeOptions`) reads its roster from exactly those
/// two fields — so the picker came up empty and a task could not be assigned to anyone.
///
/// Stored as JSON in one attribute rather than as Core Data relations, matching how
/// `recentlyCompletedWindowJSON` already carries structured list state: the roster is read and
/// written whole, never queried across, so a relation would buy nothing and cost a migration.
enum ListRosterCache {

    /// What a cached list remembers about its people.
    struct Roster: Codable, Equatable {
        var owner: User?
        var members: [ListMember]?
    }

    /// Always answers — an unreadable or absent roster is an empty one, never a crash. Core Data is
    /// only read now, by the one-time `CoreUpgrade` seed; the writer is gone, and its `encode` half
    /// went with it (AITD-532).
    static func decode(_ json: String?) -> Roster {
        guard let json, let data = json.data(using: .utf8),
              let roster = try? JSONDecoder().decode(Roster.self, from: data)
        else { return Roster(owner: nil, members: nil) }
        return roster
    }
}
