import Foundation

/// What a pulled Google Tasks item means for the local twin (Task ba4c9c84).
///
/// These three decisions lived inline in `GoogleTasksSyncService.sync(link:)`, a 450-line method
/// with no tests. They are the ones that matter — the engine around them is plumbing, but these
/// answer "what does a remote deletion mean", "what counts as the same parent", and "when must we
/// refuse to bring something back".
///
/// Pure on purpose: sync bugs cost users their data, and a decision you cannot run in a test is a
/// decision nobody checks.
enum GoogleTasksPull {

    enum Outcome: Equatable {
        /// Google says the item is gone and we hold a twin for it — delete the twin.
        case deleteLocalTwin
        /// Google says gone, but there is nothing on our side to remove.
        case ignoreDeletion
        /// We deleted this locally and let Google know. Never import it again: re-importing would
        /// undo the user's deletion, and would do so on every pass forever.
        case skipResurrection
        /// An ordinary create or update.
        case apply
    }

    /// - Parameters:
    ///   - hasLink: we hold a task-link row for this remote id.
    ///   - hasLocalTask: the linked local task still exists.
    ///   - isTombstoned: we deleted this remote id ourselves.
    static func outcome(isRemoteDeleted: Bool,
                        hasLink: Bool,
                        hasLocalTask: Bool,
                        isTombstoned: Bool) -> Outcome {
        if isRemoteDeleted {
            // Both a missing link and an already-deleted local task leave nothing to remove.
            return (hasLink && hasLocalTask) ? .deleteLocalTwin : .ignoreDeletion
        }
        // Only refuse when the link is gone too. A tombstone says "do not bring this back", not
        // "never touch this again" — a task deleted and then recreated must stay syncable.
        if isTombstoned, !hasLink { return .skipResurrection }
        return .apply
    }

    /// The key a pulled subtask's parent resolves against.
    ///
    /// Scoped to the container because Google reuses short task ids across task lists — an unscoped
    /// key would let a subtask in one list adopt a parent in another. Google also sends an empty
    /// string rather than omitting the field when there is no parent, so "" must mean nil or every
    /// top-level task becomes the child of an id that does not exist.
    static func parentKey(containerId: String, rawParent: String?) -> String? {
        guard let rawParent, !rawParent.isEmpty else { return nil }
        return "\(containerId):\(rawParent)"
    }
}
