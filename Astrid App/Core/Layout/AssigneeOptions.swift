import Foundation

/// Who a task can be assigned to, and in what order (task 1484ea4a).
///
/// Jon: "Quick assignment picker on board view doesn't list ai agents. It should make sure you
/// reuse the same assignment as in task details and list view. Code reuse please."
///
/// All three iOS surfaces render `InlineAssigneePicker`, but the picker built its option list in
/// a computed property inside the view — so "who can this be assigned to" was a view detail
/// rather than a rule: untestable, and free to differ with whatever the surrounding screen had
/// loaded.
///
/// THE ORDER IS A CROSS-PLATFORM CONTRACT (AITD-401). `astrid-web`'s
/// `components/priority-assignee-picker.tsx` states it outright — *"Sort users: AI agents first,
/// then current user, then alphabetically"* — so it is not a per-platform preference. `build`
/// below is the one implementation of it; `MacAssigneeOptions` shapes its own rows for the Mac
/// picker but asks this for who and in what order, because the two had already drifted: the Mac
/// sorted the current user first and offered no agents at all.
///
/// AI AGENTS ARE NOT LIST MEMBERS. They come from the account, not from the task's lists, so
/// they are added unconditionally — including when the task's lists are not in `availableLists`
/// at all, which is the board's case: its cards carry a project list plus a status list, and
/// neither is guaranteed to be loaded on the surface showing the picker.
enum AssigneeOptions {

    /// THE rule: de-duplicate by id, then order the way the web picker does.
    ///
    /// `roster` is whoever the calling surface has — iOS derives it from the task's lists (see
    /// the overload below), the Mac passes the members it fetched plus the task's current
    /// assignee. Agents are separate because they are NOT list members: they come from the
    /// account, so they are offered whatever the roster turned out to be.
    static func build(roster: [User], aiAgents: [User], currentUser: User?) -> [User] {
        var byId: [String: User] = [:]
        for user in roster { note(user, into: &byId) }
        for agent in aiAgents { note(agent, into: &byId) }

        return byId.values.sorted { a, b in
            // "AI agents first, then current user, then alphabetically" — astrid-web
            // components/priority-assignee-picker.tsx. Changing this changes it on three
            // platforms, so change it there too or not at all.
            let aIsAgent = a.isAIAgent == true, bIsAgent = b.isAIAgent == true
            if aIsAgent != bIsAgent { return aIsAgent }
            if let currentUser {
                if a.id == currentUser.id { return true }
                if b.id == currentUser.id { return false }
            }
            let aName = a.name ?? a.email ?? "", bName = b.name ?? b.email ?? ""
            // Id as the tiebreaker so the order is stable rather than dictionary order.
            return aName == bName ? a.id < b.id : aName < bName
        }
    }

    /// RICHEST RECORD WINS. The same person can arrive twice — a member row the server never
    /// hydrated, and the same id again as the task's assignee with a real name and photo. Taking
    /// whichever came last would sometimes put a bare id where a name belongs, which is the bug
    /// `AssigneeResolver` exists to prevent downstream.
    private static func note(_ user: User, into byId: inout [String: User]) {
        guard let existing = byId[user.id] else { byId[user.id] = user; return }
        if existing.name == nil, user.name != nil { byId[user.id] = user }
    }

    /// The iOS surfaces' way in: the roster comes from the task's own lists.
    static func build(availableLists: [TaskList],
                      taskListIds: [String],
                      discoveredUsers: [User] = [],
                      aiAgents: [User],
                      currentUser: User?) -> [User] {
        var roster: [User] = []

        let taskLists = availableLists.filter { taskListIds.contains($0.id) }
        for list in taskLists {
            if let owner = list.owner { roster.append(owner) }
            roster.append(contentsOf: (list.listMembers ?? []).compactMap(\.user))
        }

        roster.append(contentsOf: discoveredUsers)

        // A task with no resolvable lists — "My Tasks", or a board card whose lists this screen
        // has not loaded — still has to offer you, or the picker comes up empty.
        if taskLists.isEmpty, let currentUser { roster.append(currentUser) }

        return build(roster: roster, aiAgents: aiAgents, currentUser: currentUser)
    }
}
