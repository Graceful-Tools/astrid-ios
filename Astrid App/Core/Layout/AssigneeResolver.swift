import Foundation

/// Turns an assignee id into the richest `User` we can find for it (Task 42013da7).
///
/// The avatar used to be resolved from `availableMembers` alone. That list holds the CURRENT
/// list's members, so picking anyone it did not contain — someone just added by email, a member of
/// another list, an agent fetched separately — resolved to nothing, and the view kept drawing
/// whoever it had drawn last. That is the "sometimes the profile photo doesn't change" report.
///
/// Every source is consulted, richest first. The id being asked for always wins over the task's
/// embedded assignee, because a stale embedded record is precisely how the PREVIOUS person stays
/// on screen.
enum AssigneeResolver {

    static func resolve(id: String?, members: [User], taskAssignee: User?) -> User? {
        guard let id, !id.isEmpty else { return nil }

        // 1. The member record: has name and photo.
        if let member = members.first(where: { $0.id == id }) { return member }

        // 2. The task's own assignee — but ONLY when it is the same person.
        if let taskAssignee, taskAssignee.id == id { return taskAssignee }

        // 3. Nothing loaded yet: a minimal User still resolves a photo through UserImageCache,
        //    and still renders initials from the email. What it must never do is resolve to nil,
        //    which is what left the old avatar in place.
        return User(id: id, email: nil, name: nil, image: nil)
    }

    /// Identity for the avatar view. SwiftUI reuses a view whose identity has not changed, so
    /// without keying on the assignee the image stays put when the person changes.
    static func avatarIdentity(for id: String?) -> String {
        id?.isEmpty == false ? "assignee:\(id!)" : "assignee:none"
    }
}
