import Foundation

/// Who a task can be assigned to, and in what order (task 1484ea4a).
///
/// Jon: "Quick assignment picker on board view doesn't list ai agents. It should make sure you
/// reuse the same assignment as in task details and list view. Code reuse please."
///
/// All three iOS surfaces render `InlineAssigneePicker`, but the picker built its option list in
/// a computed property inside the view — so "who can this be assigned to" was a view detail
/// rather than a rule: untestable, and free to differ with whatever the surrounding screen had
/// loaded. The Mac already states this as data (`MacAssigneeOptions.build`); this is the iOS
/// half, so the three surfaces and the two platforms cannot drift.
///
/// AI AGENTS ARE NOT LIST MEMBERS. They come from the account, not from the task's lists, so
/// they are added unconditionally — including when the task's lists are not in `availableLists`
/// at all, which is the board's case: its cards carry a project list plus a status list, and
/// neither is guaranteed to be loaded on the surface showing the picker.
enum AssigneeOptions {

    static func build(availableLists: [TaskList],
                      taskListIds: [String],
                      aiAgents: [User],
                      currentUser: User?) -> [User] {
        var byId: [String: User] = [:]

        let taskLists = availableLists.filter { taskListIds.contains($0.id) }
        for list in taskLists {
            if let owner = list.owner { byId[owner.id] = owner }
            for member in list.listMembers ?? [] {
                if let user = member.user { byId[user.id] = user }
            }
        }

        for agent in aiAgents { byId[agent.id] = agent }

        // A task with no resolvable lists — "My Tasks", or a board card whose lists this screen
        // has not loaded — still has to offer you, or the picker comes up empty.
        if taskLists.isEmpty, let currentUser { byId[currentUser.id] = currentUser }

        return byId.values.sorted { a, b in
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
}
