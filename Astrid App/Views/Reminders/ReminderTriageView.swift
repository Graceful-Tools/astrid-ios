import SwiftUI

/// The triage deck a reminder opens (AITD-441): one task per screen, a swipe per decision.
///
/// The rules — which tasks, which swipe means what, where "Tomorrow" lands — are in
/// `ReminderTriage`; this view only draws the deck and reports decisions. Every swipe also has a
/// labelled button beneath the card, which is how the gestures are discovered in the first
/// place and how VoiceOver and Switch Control reach them at all.
struct ReminderTriageView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let deck: [Task]
    /// Nil when no assistant is known, which disables the up swipe rather than failing it.
    let assistantName: String?
    let onDecide: (Task, ReminderTriage.Action) -> Void

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var openTask: Task?

    private var current: Task? { deck.indices.contains(index) ? deck[index] : nil }

    /// The decision the card would make if let go now — lights up the matching button.
    private var pending: ReminderTriage.Action? {
        guard let action = ReminderTriage.action(forDragX: drag.width, y: drag.height),
              isEnabled(action) else { return nil }
        return action
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing16) {
                header

                if let task = current {
                    Spacer(minLength: 0)
                    card(for: task)
                        .id(task.id)
                        .offset(drag)
                        .rotationEffect(.degrees(Double(drag.width) / 20))
                        .gesture(dragGesture(for: task))
                        .onTapGesture { openTask = task }
                        .transition(.opacity)
                    Spacer(minLength: 0)
                    actionButtons(for: task)
                } else {
                    Spacer()
                    caughtUp
                    Spacer()
                }
            }
            .padding(Theme.spacing16)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background((colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary).ignoresSafeArea())
            .navigationDestination(item: $openTask) { task in
                TaskDetailViewNew(task: task)
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text(NSLocalizedString("reminders.triage.title", comment: "Triage deck title"))
                .font(Theme.Typography.title3())
                .fontWeight(.semibold)
            Spacer()
            if current != nil {
                Text(String(format: NSLocalizedString("reminders.triage.progress", comment: "3 of 7"),
                            index + 1, deck.count))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(mutedText)
                    .monospacedDigit()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(mutedText)
            }
            .accessibilityLabel(NSLocalizedString("reminders.triage.close", comment: "Close triage"))
        }
    }

    private func card(for task: Task) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            if let listName = task.lists?.first?.name {
                Text(listName)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(mutedText)
            }
            Text(task.title)
                .font(Theme.Typography.title2())
                .fontWeight(.semibold)
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Label(DueDateLabel.text(for: task.dueDateTime, isAllDay: task.isAllDay), systemImage: "calendar")
                .font(Theme.Typography.body())
                .foregroundColor(task.isOverdue ? Theme.error : mutedText)
            if !task.description.isEmpty {
                Text(task.description)
                    .font(Theme.Typography.body())
                    .foregroundColor(mutedText)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(Theme.spacing24)
        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(pending.map(color(for:)) ?? (colorScheme == .dark ? Theme.Dark.border : Theme.border),
                        lineWidth: pending == nil ? 1 : 3)
        )
        .shadow(radius: 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(NSLocalizedString("reminders.triage.card_hint", comment: "Opens the task"))
    }

    /// Laid out as the swipes are: Astrid above, Keep below, Complete left, Tomorrow right.
    private func actionButtons(for task: Task) -> some View {
        VStack(spacing: Theme.spacing8) {
            actionButton(.assignToAssistant, task: task)
            HStack(spacing: Theme.spacing8) {
                actionButton(.complete, task: task)
                actionButton(.postpone, task: task)
            }
            actionButton(.keep, task: task)
        }
    }

    private func actionButton(_ action: ReminderTriage.Action, task: Task) -> some View {
        let highlighted = pending == action
        return Button { decide(action, on: task) } label: {
            Label(title(for: action), systemImage: symbol(for: action))
                .font(Theme.Typography.headline())
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing12)
                .background(highlighted ? color(for: action) : (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary))
                .foregroundColor(highlighted ? .white : color(for: action))
                .cornerRadius(12)
        }
        .disabled(!isEnabled(action))
        .opacity(isEnabled(action) ? 1 : 0.4)
    }

    private var caughtUp: some View {
        VStack(spacing: Theme.spacing16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text(NSLocalizedString("reminders.triage.caught_up", comment: "All caught up"))
                .font(Theme.Typography.title2())
                .fontWeight(.semibold)
            Button(NSLocalizedString("reminders.triage.done", comment: "Done")) { dismiss() }
                .font(Theme.Typography.headline())
                .padding(.horizontal, Theme.spacing32)
                .padding(.vertical, Theme.spacing12)
                .background(Theme.accent)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    // MARK: - Behaviour

    private func dragGesture(for task: Task) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if let action = ReminderTriage.action(forDragX: value.translation.width, y: value.translation.height),
                   isEnabled(action) {
                    decide(action, on: task)
                } else {
                    withAnimation(.spring()) { drag = .zero }
                }
            }
    }

    private func decide(_ action: ReminderTriage.Action, on task: Task) {
        if action == .complete {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        onDecide(task, action)
        withAnimation(.easeOut(duration: 0.2)) {
            drag = .zero
            index += 1
        }
    }

    private func isEnabled(_ action: ReminderTriage.Action) -> Bool {
        action != .assignToAssistant || assistantName != nil
    }

    private func title(for action: ReminderTriage.Action) -> String {
        switch action {
        case .assignToAssistant:
            return String(format: NSLocalizedString("reminders.triage.assign_to", comment: "Assign to Astrid"),
                          assistantName ?? Brand.appName)
        case .keep: return NSLocalizedString("reminders.triage.keep", comment: "Keep")
        case .complete: return NSLocalizedString("reminders.complete", comment: "Complete")
        case .postpone: return NSLocalizedString("picker.tomorrow", comment: "Tomorrow")
        }
    }

    private func symbol(for action: ReminderTriage.Action) -> String {
        switch action {
        case .assignToAssistant: return "arrow.up"
        case .keep: return "arrow.down"
        case .complete: return "arrow.left"
        case .postpone: return "arrow.right"
        }
    }

    private func color(for action: ReminderTriage.Action) -> Color {
        switch action {
        case .assignToAssistant: return Theme.accent
        case .keep: return mutedText
        case .complete: return .green
        case .postpone: return .orange
        }
    }

    private var mutedText: Color { colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted }
}
