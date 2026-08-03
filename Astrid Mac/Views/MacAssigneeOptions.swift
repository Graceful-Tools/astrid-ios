//  MacAssigneeOptions.swift
//  The people the Mac task detail's Who picker can offer.
//
//  The picker was a plain `Picker` over `Text(m.user?.displayName ?? m.userId)`, which drew no
//  avatar at all and, when a member record had not hydrated, put a raw UUID on screen as if it
//  were somebody's name. Deciding WHO is on the list — and making sure each of them arrives
//  with a User an avatar can be built from — is ordinary logic, so it lives here with tests
//  rather than inline in the view.

#if os(macOS)
import Foundation

struct MacAssigneeOption: Identifiable, Equatable {
    /// nil means "no one".
    let userId: String?
    let user: User?
    let isCurrentUser: Bool

    var id: String { userId ?? "__unassigned__" }
    var isUnassigned: Bool { userId == nil }

    var displayName: String {
        guard let user else { return NSLocalizedString("No one", comment: "") }
        return user.displayName
    }
}

enum MacAssigneeOptions {

    /// Ordered: no one, then you, then everyone else alphabetically.
    ///
    /// `taskAssignee` is folded in so a task assigned to someone outside this list — added by
    /// email, a member of another list, an agent — still shows who holds it. Without that the
    /// picker cannot represent its own current value.
    static func build(members: [ListMember],
                      currentUserId: String?,
                      taskAssignee: User?) -> [MacAssigneeOption] {

        var byId: [String: User] = [:]
        var order: [String] = []

        func note(_ id: String, _ user: User?) {
            if byId[id] == nil { order.append(id) }
            // Richest record wins: a hydrated member beats a bare id placeholder.
            if let user, byId[id]?.name == nil { byId[id] = user }
            else if byId[id] == nil { byId[id] = user }
        }

        for member in members { note(member.userId, member.user) }
        if let taskAssignee { note(taskAssignee.id, taskAssignee) }

        let people: [MacAssigneeOption] = order.map { id in
            // Never nil: AssigneeResolver falls back to a minimal User, which still renders
            // initials and can still resolve a cached photo — where a raw id renders nothing.
            let resolved = AssigneeResolver.resolve(id: id,
                                                    members: byId.values.map { $0 },
                                                    taskAssignee: taskAssignee)
            return MacAssigneeOption(userId: id,
                                     user: resolved,
                                     isCurrentUser: id == currentUserId)
        }

        let sorted = people.sorted { lhs, rhs in
            // You first — self-assignment is the common case and shouldn't need hunting for.
            if lhs.isCurrentUser != rhs.isCurrentUser { return lhs.isCurrentUser }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        return [MacAssigneeOption(userId: nil, user: nil, isCurrentUser: false)] + sorted
    }
}
#endif
