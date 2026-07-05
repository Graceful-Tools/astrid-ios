import Foundation

/// Guards the push half of a sync pass against cross-container corruption.
///
/// Task-link rows are fetched by the task's CURRENT list membership, but a
/// link records the container (GitHub `owner/repo`, Google tasklist) it was
/// created against. If a task is in two linked lists — or is moved between
/// them — the "other" container's sync pass sees the link in its `byTaskId`
/// map and, with no guard, PATCHes a remote item in the WRONG container. For
/// GitHub the number collides with a real, unrelated issue (title/body/state
/// clobbered, closed if the task is completed); for Google the id 404s and
/// the push retries forever.
///
/// The deletion phases already filter by container; the push phases did not.
/// This makes the rule explicit and unit-testable.
enum SyncContainerGuard {
    /// True when an existing link may be pushed during the pass for
    /// `passContainerId`. A link belonging to a different container must be
    /// skipped — its own container's pass will handle it.
    static func mayPush(linkContainerId: String, passContainerId: String) -> Bool {
        linkContainerId == passContainerId
    }
}
