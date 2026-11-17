import AstridCore
import Foundation

/// What the control at the leading edge of a task shows (Task 42013da7).
///
/// It answers "whose task is this?". It had only two answers — someone else's photo, or a
/// checkbox — and "unassigned" was folded in with "mine", so a task nobody owns looked exactly
/// like a task you own. Nobody-assigned is its own state and gets its own mark.
///
/// One rule, used by the task row, the task detail and quick add, so the same task cannot be
/// depicted three different ways. Web mirrors it (see the companion task).
enum TaskLeadingControl: Equatable {
    /// Yours: the checkbox, which is also how you complete it.
    case checkbox
    /// Someone else's: their photo, in a priority-coloured square.
    case avatar(String)
    /// Nobody's yet.
    case unassigned

    /// Shared with `AssigneeResolver` so the mark you PICK in the assignee list is the mark you
    /// then SEE on the task.
    static var unassignedGlyph: String { AssigneeResolver.unassignedGlyph }

    /// Your own task is the checkbox, because the checkbox is how you complete it. Someone
    /// else's shows their photo; nobody's shows the "U".
    ///
    /// There used to be a second answer for your own task — your photo — in the Project task
    /// layout (task 132d7b3f). That layout is gone from every client (ADEV-70, web ADEV-56).
    ///
    /// Asked of astrid-core (`rows::LeadingControl::for_task`, AITD-622), which shares the rule
    /// with web and Windows. The surface does not change the mark, only what tapping it does.
    static func kind(assigneeId: String?,
                     currentUserId: String?) -> TaskLeadingControl {
        let answer = CoreRules.leadingControl(assigneeId: assigneeId, currentUserId: currentUserId,
                                              surface: "listRow")
        switch answer?.kind {
        case .checkbox: return .checkbox
        case .avatar(let id): return .avatar(id)
        case .unassigned, .copy: return .unassigned
        case nil:
            // The core could not answer: show whose it is, never a checkbox — the mark that
            // finishes a task on a tap is not one to draw on a guess.
            guard let assigneeId, !assigneeId.isEmpty else { return .unassigned }
            return .avatar(assigneeId)
        }
    }

    /// The assignee this mark depicts — what the core is asked about. A checkbox is always the
    /// reader's own task.
    fileprivate func assigneeId(currentUserId: String?) -> String? {
        switch self {
        case .checkbox: return currentUserId
        case .avatar(let id): return id
        case .unassigned: return nil
        }
    }
}

/// WHERE a task's leading control is being drawn.
///
/// The rule below once asked only which Appearance mode was on, and a mode cannot tell a board
/// card from a list row: the checkbox finished tasks on board cards too, the trapdoor task
/// 9be8cb1b removed from the board (task f9d7ed42). A surface is something the call site knows.
enum TaskLeadingControlSurface: Equatable {
    /// A card in a project board column.
    case boardCard
    /// A row in a list.
    case listRow
    /// The task detail screen or panel.
    case detail

    /// astrid-core's name for the surface (`rows::Surface::from_wire`).
    var wireValue: String {
        switch self {
        case .boardCard: return "boardCard"
        case .listRow: return "listRow"
        case .detail: return "detail"
        }
    }
}

/// What clicking or tapping the leading control does.
///
/// Two answers, not three. AITD-363 briefly added a `confirmCompletion` tap for someone else's
/// task in task details; AITD-375 replaced it with the options popover on every surface, moving
/// the confirmation onto that popover's Complete button, and AITD-381 dropped it. ADEV-70 put it
/// back on the Complete button, for any task that is not yours (`completionNeedsConfirmation`).
/// A tap either finishes the task or offers you the choices.
enum TaskLeadingControlAction: Equatable {
    case complete
    case openPicker
}

extension TaskLeadingControl {

    /// Complete the task, or open the picker?
    ///
    /// A BOARD CARD always opens the picker. A board is where a task has a
    /// status, so the control is how you set it — and completing outright from a card is the
    /// trapdoor described above (tasks 9be8cb1b, f9d7ed42).
    ///
    /// A LIST ROW completes, because that is what a checkbox means when the task is not on a
    /// board.
    ///
    /// SOMEONE ELSE'S TASK OPENS THE POPOVER, EVERYWHERE (AITD-375). Jon: "when not yours ...
    /// it should give the popover to show assignment, complete, priority and status options."
    ///
    /// This is checked before the surface, because it holds on all of them, and it settles two
    /// things that used to disagree. A list ROW completed another person's task outright on a
    /// tap — one stray touch on a small photo in a dense list, no confirmation and no obvious way
    /// back. Task DETAILS did the opposite and offered no way to complete it at all, then briefly
    /// (AITD-363) a bespoke confirm-on-tap. Neither is right, and they were not even the same
    /// wrong: one screen finished the task, another would not.
    ///
    /// The popover answers both. It cannot be triggered by accident the way an outright
    /// completion can, it carries assignment and priority and board state — which are usually
    /// what you actually wanted when you reached for someone else's task — and completion is
    /// still there, on the popover's own Complete button.
    ///
    /// NOBODY'S TASK OPENS IT TOO (AITD-382), but it arrives there by a different road. The
    /// guard above is about tasks that belong to someone — another person or an agent, both of
    /// them `.avatar(id)` with an id that is not yours. An unassigned task is deliberately NOT
    /// "someone else's", so it falls past that guard, and what catches it is the surface switch
    /// asking whether the mark is a checkbox at all. Since task 42013da7 it is not: a task
    /// nobody owns draws the "U" glyph, precisely because drawing it as a checkbox made it look
    /// like a task you own. Completing on a tap is what a checkbox means; it is not what that
    /// glyph means. Jon, AITD-382: "unassigned ... agents, and tasks assigned to others should
    /// all behave the same".
    ///
    /// One function for both platforms, so a card cannot mean one thing on the Mac and another
    /// on the phone — the same reason `kind` is shared.
    static func action(surface: TaskLeadingControlSurface,
                       kind: TaskLeadingControl,
                       currentUserId: String?) -> TaskLeadingControlAction {
        // Asked of astrid-core (`rows::LeadingControl::action`, AITD-622), which has followed
        // exactly this rule since core e0d8ce7 (AWTD2-214, CONTRACTS D62). A failed answer opens
        // the picker: it cannot finish a task by accident, and completion is on the picker.
        let answer = CoreRules.leadingControl(assigneeId: kind.assigneeId(currentUserId: currentUserId),
                                              currentUserId: currentUserId,
                                              surface: surface.wireValue)
        return answer?.action == .complete ? .complete : .openPicker
    }

    /// Is this control showing a task that belongs to somebody else?
    ///
    /// Asked of the KIND, so it cannot disagree with the mark on screen — `.avatar` already
    /// carries whose face it is.
    ///
    /// An unknown current user counts as someone else's: we cannot show it is yours, and the
    /// safe answer is the one that asks first.
    func isSomeoneElses(currentUserId: String?) -> Bool {
        Self.isSomeoneElsesTask(assigneeId: assigneeId(currentUserId: currentUserId),
                                currentUserId: currentUserId)
    }

    /// Does this task belong to somebody else, asked of the raw ids?
    ///
    /// Decides the MARK and what the options popover carries. It is deliberately not the
    /// completion-confirmation question: an unassigned task is nobody else's here, but completing
    /// it still asks first (`completionNeedsConfirmation`, ADEV-70).
    ///
    /// Takes the raw ids rather than a `kind`, because the thing asking is not a leading control
    /// and has no mark to ask about.
    static func isSomeoneElsesTask(assigneeId: String?, currentUserId: String?) -> Bool {
        // Asked of astrid-core (`leadingPicker`, AWTD2-216; AITD-622). Nobody's task is nobody
        // else's. If the core cannot answer, an assigned task counts as someone else's: we cannot
        // show it is yours, and the safe answer is the one that asks first.
        guard let assigneeId, !assigneeId.isEmpty else { return false }
        return CoreRules.leadingPicker(surface: TaskLeadingControlSurface.listRow.wireValue,
                                       assigneeId: assigneeId,
                                       currentUserId: currentUserId)?.isSomeoneElsesTask ?? true
    }

    /// Does completing this task ask "Complete this task?" first? (ADEV-70, web ADEV-56)
    ///
    /// IT IS NOT YOURS — that is the whole rule. Jon: "show confirmation before completing a task
    /// that isn't [assigned to me] (including unassigned)." Mirrors `completionNeedsConfirmation`
    /// in astrid-web `lib/task-leading-control.ts`.
    ///
    /// - Unassigned (`nil` or `""`) asks. That is the difference from `isSomeoneElsesTask`, which
    ///   still calls nobody's task nobody else's for the mark and the popover.
    /// - An unknown viewer asks: we cannot show the task is yours.
    /// - REOPENING never asks (`completed` is the task's state now). Undoing a completion takes
    ///   nothing away from anyone.
    static func completionNeedsConfirmation(assigneeId: String?,
                                            currentUserId: String?,
                                            completed: Bool) -> Bool {
        if completed { return false }
        guard let currentUserId, !currentUserId.isEmpty else { return true }
        return assigneeId != currentUserId
    }

    /// Does the options popover carry the board-state section?
    ///
    /// Someone else's task gets the full set (AITD-375). The detail panel otherwise omits it
    /// because priority and assignee are already rows of their own there; that was never an
    /// argument about what the popover should offer when the popover is the only thing you get.
    ///
    /// Shared so the Mac's `MacLeadingPicker` and the phone's popovers cannot offer different
    /// choices for the same task.
    ///
    /// Asked of astrid-core (`leadingPicker`, AWTD2-216; AITD-622) with the raw ids, so "is it
    /// someone else's" is decided by the same rule as `isSomeoneElsesTask`. A failed answer offers
    /// the full set: an extra section is harmless, a missing one hides the board state.
    static func pickerShowsProjectState(surface: TaskLeadingControlSurface,
                                        assigneeId: String?,
                                        currentUserId: String?) -> Bool {
        CoreRules.leadingPicker(surface: surface.wireValue,
                                assigneeId: assigneeId,
                                currentUserId: currentUserId)?.pickerShowsProjectState ?? true
    }
}
