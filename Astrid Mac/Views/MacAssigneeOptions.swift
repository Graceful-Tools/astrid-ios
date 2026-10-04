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

    /// What the Mac's pickers ask about `task`: its lists, the agents the app keeps (the Mac fills
    /// that cache itself since AITD-399), and who is signed in.
    ///
    /// WHO and IN WHAT ORDER is astrid-core's `assigneeOptions` (AITD-461, CONTRACTS D47) — the
    /// rule iOS's picker reads, so the Mac follows iOS: no one, then agents, then you, then
    /// everyone by name; a member whose record never hydrated is not offered.
    @MainActor
    static func question(for task: Task) -> AssigneeQuestion {
        AssigneeQuestion(listIds: taskListMembershipIdsInOrder(task),
                         agents: AIAgentCache.shared.load() ?? [],
                         currentUser: AuthManager.shared.currentUser)
    }

    /// The picker's rows from the core's answer: only the SHAPING is the Mac's — the "no one"
    /// row first, `isCurrentUser`, and a `User` every face can be drawn from.
    static func rows(_ answer: AssigneeAnswer?, currentUserId: String?) -> [MacAssigneeOption] {
        let people = (answer?.people ?? []).map { user in
            MacAssigneeOption(userId: user.id, user: user, isCurrentUser: user.id == currentUserId)
        }
        return [MacAssigneeOption(userId: nil, user: nil, isCurrentUser: false)] + people
    }
}
#endif
