import Foundation

/// Whether task details show a BOARD STATE row (AITD-327 on the Mac, AITD-332 on iOS).
///
/// The rule narrows an older, blunter one rather than reversing it. The quick changer reasoned
/// that "a board column is a project idea, and a row for it in the list layout rebuilds the
/// hybrid" the display-mode setting exists to end. That is sound for a task with no board column
/// — a row for a state it cannot have IS the hybrid. It is not sound for a task that is on a
/// board: there the column is real information the list layout was simply hiding, and switching
/// display modes was the only way to reach it. The `isInProject` condition is the whole design.
///
/// Stated once, here, because both platforms ask it. The Mac spelled it inside `MacTaskFields`
/// first; iOS would have spelled it again in `TaskDetailViewNew`, and a layout question answered
/// separately on each platform is how Priority-before-Who ended up shipped on both at the same
/// time (task c8a1ff51) — the same mistake twice is what two views deciding for themselves
/// produces. Mirrors nothing on web yet; when the web board detail grows the row, this is the
/// rule it is copying.
enum TaskDetailProjectStateRow {

    /// - Parameters:
    ///   - displayMode: the user's Appearance setting. List mode only — in project mode board
    ///     state already lives in the leading control's quick changer (task 729a190e), and a row
    ///     would say it twice in the layout that is compact on purpose.
    ///   - isInProject: whether the task has a board column at all — ask `isTaskInProject`, never
    ///     a condition written at the call site.
    ///   - isReadOnly: the public-list viewer. The row is a MOVER, not a label: its chips write.
    ///     So it follows Who and Priority, which are hidden there rather than shown as controls
    ///     that cannot be used.
    static func isVisible(displayMode: TaskDisplayMode,
                          isInProject: Bool,
                          isReadOnly: Bool) -> Bool {
        displayMode.showsSeparateAssigneeAndPriorityRows && isInProject && !isReadOnly
    }
}
