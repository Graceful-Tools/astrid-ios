import AstridCore
import SwiftUI

/// "What is it waiting for?" — asked when a move into Waiting names no condition (AITD-631).
///
/// Jon, 2026-11-12: Waiting means waiting on a date or on a task. The core refuses the move with
/// `WAITING_NEEDS_CONDITION`; `WaitingPromptPresenter` holds it, and this prompt collects:
///
/// - **Waiting until…** a day after today (an all-day due date, as web sends it), or
/// - **Waiting on…** a task, found with the same search the blocker picker uses,
/// - and **Keep assigned to me / <name>**, off by default — entering Waiting unassigns otherwise.
///
/// Confirm sends the same move again with the answer; Cancel sends nothing. One view for iOS and
/// the Mac; its copy is web's `waiting.prompt.*` keys (PRODUCT_CONTRACT §2).
struct WaitingConditionPrompt: View {
    let request: WaitingPromptPresenter.Request
    let presenter: WaitingPromptPresenter

    private enum Mode: Hashable { case until, on }

    @ThemedPalette private var palette
    @State private var mode: Mode = .until
    @State private var day: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var query = ""
    @State private var hits: [BlockerSearchHit] = []
    @State private var picked: BlockerSearchHit?
    @State private var keepAssignee = false
    @State private var sending = false
    @State private var errorMessage: String?

    private var task: Task { request.task }

    private var keepLabel: String? {
        WaitCondition.keepLabel(assigneeId: task.assigneeId,
                                assigneeName: task.assignee?.displayName,
                                currentUserId: AuthManager.shared.currentUser?.id)
    }

    private var condition: WaitCondition? {
        switch mode {
        case .until:
            return WaitCondition.isAfterToday(day) ? WaitCondition(kind: .until(day), keepAssignee: keepAssignee) : nil
        case .on:
            return picked.map { WaitCondition(kind: .on(taskId: $0.id, title: $0.title), keepAssignee: keepAssignee) }
        }
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(NSLocalizedString("waiting.prompt.title", comment: ""))
                    .font(Theme.Typography.headline())
                    .foregroundColor(palette.textPrimary)
                Text(task.title.isEmpty
                     ? NSLocalizedString("waiting.prompt.description", comment: "")
                     : String(format: NSLocalizedString("waiting.prompt.descriptionFor", comment: ""), task.title))
                    .font(Theme.Typography.subheadline())
                    .foregroundColor(palette.textSecondary)
            }

            Picker(selection: $mode) {
                Text(NSLocalizedString("waiting.prompt.until", comment: "")).tag(Mode.until)
                Text(NSLocalizedString("waiting.prompt.on", comment: "")).tag(Mode.on)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("waiting.prompt.mode")

            switch mode {
            case .until: untilSection
            case .on: onSection
            }

            if let keepLabel {
                Toggle(keepLabel, isOn: $keepAssignee)
                    .accessibilityIdentifier("waiting.prompt.keep")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.errorInk)
            }

            HStack {
                Button(NSLocalizedString("actions.cancel", comment: "")) { presenter.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(NSLocalizedString("waiting.prompt.confirm", comment: "")) { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(condition == nil || sending)
                    .accessibilityIdentifier("waiting.prompt.confirm")
            }
        }
        .padding(Theme.spacing20)
        .frame(minWidth: 320, idealWidth: 420)
        .background(palette.bgPrimary)
    }

    private var untilSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            DatePicker(NSLocalizedString("waiting.prompt.dateLabel", comment: ""),
                       selection: $day, in: tomorrow..., displayedComponents: .date)
                .accessibilityIdentifier("waiting.prompt.date")
            if !WaitCondition.isAfterToday(day) {
                Text(NSLocalizedString("waiting.prompt.dateInPast", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.errorInk)
            }
        }
    }

    private var onSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if let picked {
                Text(String(format: NSLocalizedString("waiting.prompt.picked", comment: ""), picked.title))
                    .font(Theme.Typography.subheadline())
                    .foregroundColor(palette.textPrimary)
            }
            TextField(NSLocalizedString("waiting.prompt.taskLabel", comment: ""), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("waiting.prompt.search")
            if TaskBlockers.shouldSearch(query) && hits.isEmpty {
                Text(NSLocalizedString("tasks.waitingOn.noResults", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textSecondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    ForEach(hits) { hit in
                        Button { picked = hit } label: {
                            HStack {
                                Text(hit.title)
                                    .strikethrough(hit.completed == true)
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                if picked?.id == hit.id {
                                    Image(systemName: "checkmark").foregroundColor(palette.accentInk)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, Theme.spacing4)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .task(id: query) { await search() }
    }

    private func search() async {
        // Debounce: `.task(id:)` cancels this when the query changes again.
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
        guard !_Concurrency.Task.isCancelled else { return }
        let found = (try? await TaskBlockerService.shared.candidates(query: query, task: task,
                                                                     excludedIds: [task.id])) ?? []
        guard !_Concurrency.Task.isCancelled else { return }
        hits = found
    }

    private func confirm() {
        guard let condition else { return }
        sending = true
        errorMessage = nil
        _Concurrency.Task {
            do {
                try await presenter.confirm(condition)
            } catch {
                // Waiting on a task attaches it as a blocker online, at once — the blocker picker's
                // own copy says what went wrong. A date can fail only as any task write can.
                if TaskBlockers.isCycleRefusal(error) {
                    errorMessage = NSLocalizedString("tasks.waitingOn.cycleError", comment: "")
                } else if mode == .on {
                    errorMessage = NSLocalizedString("tasks.waitingOn.addError", comment: "")
                } else {
                    errorMessage = (error as? CoreFailure)?.message ?? error.localizedDescription
                }
            }
            sending = false
        }
    }
}

extension View {
    /// Draw the Waiting prompt whenever a move into Waiting needs a condition (AITD-631). Mounted
    /// once, at each app's root, so every surface that moves a task shares it.
    func waitingConditionPrompt(_ presenter: WaitingPromptPresenter = .shared) -> some View {
        modifier(WaitingConditionPromptHost(presenter: presenter))
    }
}

private struct WaitingConditionPromptHost: ViewModifier {
    @ObservedObject var presenter: WaitingPromptPresenter

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { presenter.pending }, set: { if $0 == nil { presenter.cancel() } })) { request in
            WaitingConditionPrompt(request: request, presenter: presenter)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
        }
    }
}
