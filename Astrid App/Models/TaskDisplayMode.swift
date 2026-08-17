import Foundation

/// Which task-detail design the user sees (task 8ef7d89d).
///
/// The server stores this as a nullable string with exactly two values. The web half is live:
/// the column, both endpoints, and the Appearance selector all ship, and everyone currently
/// defaults to `list`.
///
///     GET/PATCH /api/v1/users/me/smart-tasks   (X-OAuth-Token)
///     GET/PATCH /api/user/settings             (session)
///
/// **Reads normalize, writes reject — and that asymmetry is deliberate.** Anything unknown
/// resolves to `.list` on the way in, because a row written before the column exists reads back
/// null and a build that meets a newer mode must still draw a usable screen. But the server
/// answers `400 {"error":"Invalid taskDisplayMode value"}` to a PATCH carrying anything other
/// than the two literals, so `wireValue` only ever emits one of them. A coerced value must never
/// be echoed back.
///
/// **Not the `project_mode` feature flag.** The names are close enough to cause a real mistake.
/// `project_mode` is access — may this user use projects and boards at all, a build capability
/// plus an admin grant. This is a preference the user sets in Appearance. Someone can have
/// either without the other, and neither gates the other.
///
/// Mirrors `astrid-web/lib/task-display-mode.ts`, including its two named questions, so no call
/// site spells the comparison itself. That matters here more than usual: the bug this setting
/// exists to end is the product showing a HYBRID of the two layouts, and a comparison written at
/// ten call sites is ten chances to write it differently.
enum TaskDisplayMode: String, Equatable, CaseIterable {

    /// The checkbox completes the task. Priority and assignee each get their own row in task
    /// details, in every interface including board and list view.
    case list

    /// Task details are compact. Tapping the checkbox does NOT complete the task — it reveals a
    /// popover carrying priority, assignee, board state and complete/mark-incomplete. Tasks
    /// assigned to you also show your profile photo.
    case project

    /// What the server stores, and the only thing it accepts.
    var wireValue: String { rawValue }

    /// Resolve whatever the server sent — including nothing at all.
    ///
    /// Null, absent, empty and unrecognised all mean `.list`. None of them is an error, and
    /// none of them is a third mode.
    init(stored: String?) {
        let normalized = stored?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = TaskDisplayMode(rawValue: normalized ?? "") ?? .list
    }

    // MARK: - What each mode means, asked rather than compared

    /// Whether tapping the checkbox completes the task, or opens the picker instead.
    var checkboxCompletesTask: Bool { self == .list }

    /// Whether task details use the compact layout.
    var usesCompactTaskDetail: Bool { self == .project }

    // MARK: - The stale-control trap

    /// Whether a picker is allowed to write yet.
    ///
    /// The failure this prevents hides well: a control that saves correctly but initialises to
    /// the default looks right until the screen is revisited, and then re-saving from the stale
    /// control writes `list` back over `project`. Settings must have loaded first — web carries
    /// a regression test for exactly this.
    static func mayPersistSelection(hasLoadedSettings: Bool) -> Bool {
        hasLoadedSettings
    }
}
