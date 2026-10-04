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

/// The remote item a push links to instead of creating a duplicate: the one unlinked Google item
/// with the local task's title.
///
/// A deleted (`metadata.deleted == "1"`, from `showDeleted=true`) or tombstoned item is never a
/// twin (AITD-462, astrid-core CONTRACTS D39). Linking to one made the next pass's absence
/// deletion — which reads a deleted item as absent — delete the local task: somebody who once
/// deleted "Buy milk" in Google lost every "Buy milk" they added here.
enum GooglePushTwin {
    static func find(title: String, in items: [GoogleTaskItemDTO],
                     isLinked: (String) -> Bool, tombstoned: Set<String>) -> GoogleTaskItemDTO? {
        items.first {
            $0.title == title && $0.metadata?["deleted"] != "1"
                && !tombstoned.contains($0.remoteId) && !isLinked($0.remoteId)
        }
    }
}
