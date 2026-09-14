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
        guard let user else { return Self.unassignedLabel }
        return user.displayName
    }

    /// What an unassigned task is called — the same word iOS and web use (task 6c891bce).
    ///
    /// The Mac said "No one", and passed that English text to `NSLocalizedString` as its own
    /// key. No such key exists in Localizable.strings, so all twelve translations fell back to
    /// English. It was not only inconsistent copy, it was unlocalized copy.
    ///
    /// `assignee.unassigned` is the key iOS already uses, and user-facing strings are a
    /// cross-platform contract rather than a per-platform choice (ASTRID.md rule 8).
    static let unassignedLabel = NSLocalizedString("assignee.unassigned", comment: "Unassigned")
}

enum MacAssigneeOptions {

    /// Ordered: no one, then AI agents, then you, then everyone else alphabetically.
    ///
    /// WHO and IN WHAT ORDER is `AssigneeOptions.build` (AITD-401), because that order is a
    /// cross-platform contract with the web picker, not a Mac preference. This used to sort the
    /// current user first and never offered agents at all — so the Mac could not hand a task to
    /// one, which is the very bug task 1484ea4a fixed on the iOS board. Only the row SHAPING is
    /// local: the "no one" row, `isCurrentUser`, and resolving a `User` an avatar can draw.
    ///
    /// `taskAssignee` is folded into the roster so a task assigned to someone outside this list —
    /// added by email, a member of another list, an agent — still shows who holds it. Without
    /// that the picker cannot represent its own current value.
    ///
    /// `aiAgents` defaults to the shared cache, so the three call sites need pass nothing. The
    /// Mac fills that cache itself since AITD-399; before then only iOS wrote it.
    static func build(members: [ListMember],
                      currentUserId: String?,
                      taskAssignee: User?,
                      aiAgents: [User] = AIAgentCache.shared.load() ?? []) -> [MacAssigneeOption] {

        // A member whose `user` never hydrated still has to become an option — dropping it would
        // hide a real person — so it enters the roster as a minimal User carrying just the id.
        var roster: [User] = members.map { member in
            member.user ?? User(id: member.userId, email: nil, name: nil, image: nil)
        }
        if let taskAssignee { roster.append(taskAssignee) }

        let currentUser = currentUserId.flatMap { id in roster.first { $0.id == id } }
            ?? currentUserId.map { User(id: $0, email: nil, name: nil, image: nil) }

        let ordered = AssigneeOptions.build(roster: roster, aiAgents: aiAgents, currentUser: currentUser)

        let people = ordered.map { user in
            // Never nil: AssigneeResolver falls back to a minimal User, which still renders
            // initials and can still resolve a cached photo — where a raw id renders nothing.
            MacAssigneeOption(userId: user.id,
                              user: AssigneeResolver.resolve(id: user.id,
                                                             members: ordered,
                                                             taskAssignee: taskAssignee),
                              isCurrentUser: user.id == currentUserId)
        }

        return [MacAssigneeOption(userId: nil, user: nil, isCurrentUser: false)] + people
    }
}
#endif
