import Foundation

/// What picking a person does on a list where a task may hold several (AITD-491).
///
/// A classic list keeps one assignee, so its picker replaces. A GitHub-backed board says
/// `supports.multipleAssignees`, and there a tap adds or removes one person and leaves the rest.
/// The order matters: the first id is the primary — the face a row draws and the person an
/// "assigned to you" notification is keyed on — and the server refuses a list it cannot keep
/// (astrid-web `lib/task-assignees.ts`), so the picker never builds one.
enum AssigneeSelection {

    /// The server's ceiling (`too_many_assignees`).
    static let maximum = 10

    /// Faces drawn after the primary before the rest become a count.
    static let additionalFacesShown = 3

    /// A task may hold several people when any list it is on says so.
    static func allowsMultiple(listIds: [String], lists: [TaskList]) -> Bool {
        lists.contains { listIds.contains($0.id) && $0.supportsMultipleAssignees }
    }

    /// The whole list after tapping `id` — nil is the "Unassigned" row.
    ///
    /// - Someone already there is removed; whoever follows becomes primary.
    /// - A person joins at the end, so adding never changes who is primary.
    /// - An agent goes first and replaces any other agent: a run is keyed on the primary, so one
    ///   further down would be assigned and never run (`agent_must_be_first_assignee`).
    /// - Past the ceiling a tap changes nothing rather than sending a list the server refuses.
    static func toggling(_ id: String?, in current: [String], agentIds: Set<String> = []) -> [String] {
        guard let id, !id.isEmpty else { return [] }
        if current.contains(id) { return current.filter { $0 != id } }
        if agentIds.contains(id) { return [id] + current.filter { !agentIds.contains($0) } }
        guard current.count < maximum else { return current }
        return current + [id]
    }

    /// The people drawn after the primary, and how many more there are than faces for them.
    static func additionalFaces(in ids: [String]) -> (shown: [String], overflow: Int) {
        let others = Array(ids.dropFirst())
        let shown = Array(others.prefix(additionalFacesShown))
        return (shown, others.count - shown.count)
    }
}
