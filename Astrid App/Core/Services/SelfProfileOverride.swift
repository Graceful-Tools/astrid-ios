import Foundation

/// The signed-in user's own name and photo, as last saved on this device.
struct SelfProfile: Equatable {
    let userId: String
    let name: String?
    let image: String?
}

/// Lays the signed-in user's saved name and photo over every copy of them embedded in cached
/// lists and tasks (AITD-669).
///
/// Avatars draw from the user embedded in each list (`owner`, `listMembers[].user`) and task
/// (`assignee`, `creator`, comment authors), and `User.cachedImageURL` prefers that embedded
/// image. A profile change touches no list's `updatedAt`, so sync does not refresh those copies
/// either: a new photo showed only where `AuthManager.currentUser` was read, and the old one
/// everywhere else. `ListService` and `TaskService` apply this on every publish, so a core
/// reload still carrying the stale copy cannot bring the old photo back.
@MainActor
final class SelfProfileOverride {
    static let shared = SelfProfileOverride()

    private(set) var profile: SelfProfile?

    private init() {}

    /// Record a saved profile and have both services redraw with it.
    func set(_ next: SelfProfile) {
        guard next != profile else { return }
        profile = next
        ListService.shared.reapplySelfProfile()
        TaskService.shared.rejoinLists()
    }

    /// Sign-out: the next account's lists carry its own copies.
    func clear() {
        profile = nil
    }

    func apply(to lists: [TaskList]) -> [TaskList] {
        profile.map { Self.apply($0, to: lists) } ?? lists
    }

    func apply(to tasks: [Task]) -> [Task] {
        profile.map { Self.apply($0, to: tasks) } ?? tasks
    }

    // MARK: - Pure

    static func apply(_ profile: SelfProfile, to lists: [TaskList]) -> [TaskList] {
        lists.map { list in
            var list = list
            list.owner = patched(list.owner, with: profile)
            list.listMembers = list.listMembers?.map { member in
                var member = member
                member.user = patched(member.user, with: profile)
                return member
            }
            return list
        }
    }

    static func apply(_ profile: SelfProfile, to tasks: [Task]) -> [Task] {
        tasks.map { task in
            var task = task
            task.assignee = patched(task.assignee, with: profile)
            task.creator = patched(task.creator, with: profile)
            task.comments = task.comments?.map { comment in
                var comment = comment
                comment.author = patched(comment.author, with: profile)
                return comment
            }
            return task
        }
    }

    private static func patched(_ user: User?, with profile: SelfProfile) -> User? {
        guard var user, user.id == profile.userId else { return user }
        if user.image != profile.image { user.image = profile.image }
        if user.name != profile.name { user.name = profile.name }
        return user
    }
}
