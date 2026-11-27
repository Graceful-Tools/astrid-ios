//  OrchestrationPolicyEditor.swift
//  The agent policy in list settings, iOS and Mac (ADEV-333; web AWTD-1693
//  `components/list-admin/OrchestrationPolicySection.tsx`): who takes this board's unassigned Ready
//  work, what an agent may do alone, the trade-off thresholds, and who it asks. One policy per
//  project, which the list may override field by field; a list with no project has only its own.
//
//  Every choice saves at once through `OrchestrationPolicyService`. What an unset field falls back
//  to — the "Inherited (…)" / "Default (…)" choice — is astrid-core's answer
//  (`OrchestrationPolicyRules`), never restated here. Which scopes may be edited is the server's
//  `canEdit`; a person who may edit neither sees nothing.

import SwiftUI

struct OrchestrationPolicyEditor: View {
    let list: TaskList

    @ObservedObject private var service = OrchestrationPolicyService.shared
    @ObservedObject private var goalsService = ProjectGoalsService.shared
    @ThemedPalette private var palette
    @State private var loaded = false
    @State private var failed = false

    private var view: ListOrchestrationPolicyView? { service.view(listId: list.id) }

    var body: some View {
        Form {
            if let view, view.editsAnything {
                Section {
                    Text(NSLocalizedString("orchestrationPolicy.help", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(palette.textMuted)
                }
                ForEach(view.scopes, id: \.self) { scope in
                    OrchestrationPolicyScopeSections(list: list, view: view, scope: scope,
                                                     goals: goals(view), saving: service.saving[list.id] != nil) { next in
                        save(scope: scope, policy: next)
                    }
                }
                Section(NSLocalizedString("orchestrationPolicy.effective", comment: "")) {
                    effectiveLines(view)
                }
                if failed {
                    Text(NSLocalizedString("orchestrationPolicy.saveFailed", comment: ""))
                        .foregroundColor(palette.error)
                }
            } else if !loaded {
                ProgressView()
            } else {
                Text(NSLocalizedString("orchestrationPolicy.unavailable", comment: ""))
                    .foregroundColor(palette.textMuted)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("orchestrationPolicy.title", comment: ""))
        .accessibilityIdentifier("orchestration-policy")
        .task(id: list.id) {
            await service.load(listId: list.id)
            loaded = true
            if let projectId = service.view(listId: list.id)?.projectId {
                await goalsService.load(projectId: projectId)
            }
        }
    }

    private func goals(_ view: ListOrchestrationPolicyView) -> [ProjectGoal] {
        view.projectId.flatMap { goalsService.goals(projectId: $0)?.goals } ?? []
    }

    private func save(scope: OrchestrationPolicyScope, policy: PolicyDocument?) {
        _Concurrency.Task {
            failed = false
            if await service.save(listId: list.id, scope: scope, policy: policy) {
                // The Policy sort is offered only while a trade-off policy applies (ADEV-321).
                await ListTradeoffPolicyService.shared.load(listId: list.id)
            } else {
                failed = true
            }
        }
    }

    @ViewBuilder
    private func effectiveLines(_ view: ListOrchestrationPolicyView) -> some View {
        let labels = OrchestrationPolicyLabels(list: list)
        let effective = view.effective
        Group {
            line(NSLocalizedString("orchestrationPolicy.routing.label", comment: ""),
                 labels.routing(effective.assignTo ?? nil))
            ForEach(PolicyAutonomyField.allCases, id: \.self) { field in
                line(labels.action(field), effective.autonomy(field).map(labels.autonomy) ?? "")
            }
            line(NSLocalizedString("orchestrationPolicy.escalation.label", comment: ""),
                 effective.escalation.map(labels.escalation) ?? "")
            line(NSLocalizedString("orchestrationPolicy.tradeoff.title", comment: ""),
                 NSLocalizedString(effective.tradeoffStated ? "orchestrationPolicy.tradeoff.stated" : "orchestrationPolicy.tradeoff.none",
                                   comment: ""))
        }
        .font(Theme.Typography.caption1())
        .foregroundColor(palette.textMuted)
    }

    private func line(_ label: String, _ value: String) -> some View {
        Text(String(format: NSLocalizedString("orchestrationPolicy.line", comment: ""), label, value))
    }
}

/// The words for each value, and who is on the list to route to or ask.
struct OrchestrationPolicyLabels {
    let list: TaskList

    /// Everyone with a role on the list, once each.
    var members: [User] {
        var seen = Set<String>()
        let all = [list.owner].compactMap { $0 } + (list.admins ?? []) + (list.members ?? [])
            + (list.listMembers ?? []).compactMap(\.user)
        return all.filter { seen.insert($0.id).inserted }
    }

    /// The agents on the list, by mailbox — what routing names.
    var agents: [String] {
        var seen = Set<String>()
        return members.compactMap(\.agentMailbox).filter { seen.insert($0).inserted }
    }
    var people: [User] { members.filter { $0.isAIAgent != true } }

    func autonomy(_ value: PolicyAutonomy) -> String {
        NSLocalizedString("orchestrationPolicy.autonomy.\(value.rawValue)", comment: "")
    }

    func action(_ field: PolicyAutonomyField) -> String {
        NSLocalizedString("orchestrationPolicy.action.\(field.rawValue)", comment: "")
    }

    func level(_ value: PolicyLevel) -> String {
        NSLocalizedString("orchestrationPolicy.level.\(value.rawValue)", comment: "")
    }

    func probability(_ value: Double) -> String {
        String(format: NSLocalizedString("orchestrationPolicy.tradeoff.probability", comment: ""), Int((value * 100).rounded()))
    }

    func routing(_ assignTo: String?) -> String {
        assignTo ?? NSLocalizedString("orchestrationPolicy.routing.anyAgent", comment: "")
    }

    func escalation(_ value: PolicyEscalation) -> String {
        switch value {
        case .listOwner: return NSLocalizedString("orchestrationPolicy.escalation.listOwner", comment: "")
        case .taskCreator: return NSLocalizedString("orchestrationPolicy.escalation.taskCreator", comment: "")
        case .people(let ids):
            return ids.map { id in
                let person = members.first { $0.id == id }
                return person?.name ?? person?.email ?? id
            }.joined(separator: ", ")
        }
    }

    func person(_ user: User) -> String { user.name ?? user.email ?? user.id }
}

/// One scope's rows: routing, the autonomy actions, the trade-off policy, escalation.
private struct OrchestrationPolicyScopeSections: View {
    let list: TaskList
    let view: ListOrchestrationPolicyView
    let scope: OrchestrationPolicyScope
    let goals: [ProjectGoal]
    let saving: Bool
    let onSave: (PolicyDocument?) -> Void

    @ThemedPalette private var palette

    private static let inherit = "__inherit"
    private static let anyAgent = "__any"
    private static let person = "person:"

    private var labels: OrchestrationPolicyLabels { OrchestrationPolicyLabels(list: list) }
    private var override: PolicyDocument { view.override(scope) ?? PolicyDocument() }
    private var inherited: PolicyDocument? { OrchestrationPolicyRules.inherited(by: scope, in: view) }
    private var disabled: Bool { !view.canEdit(scope) || saving }

    private func inheritLabel(_ value: String) -> String {
        String(format: NSLocalizedString(scope == .project ? "orchestrationPolicy.default" : "orchestrationPolicy.inherit",
                                         comment: ""), value)
    }

    var body: some View {
        Section {
            routingPicker
            ForEach(PolicyAutonomyField.allCases, id: \.self) { field in
                autonomyPicker(field)
            }
            escalationPicker
        } header: {
            Text(NSLocalizedString("orchestrationPolicy.scope.\(scope.rawValue)", comment: ""))
        } footer: {
            Text(NSLocalizedString("orchestrationPolicy.scope.\(scope.rawValue)Help", comment: ""))
        }
        .disabled(disabled)
        .accessibilityIdentifier("orchestration-policy-\(scope.rawValue)")

        OrchestrationTradeoffSection(scope: scope, override: override, inherited: inherited,
                                     goals: goals, labels: labels, disabled: disabled,
                                     inheritLabel: inheritLabel, onSave: onSave)
    }

    // MARK: Routing

    private var routingPicker: some View {
        let stored = override.assignTo
        let selection: String = switch stored {
        case .none: Self.inherit
        case .some(.none): Self.anyAgent
        case .some(.some(let mailbox)): mailbox
        }
        var options = labels.agents
        if case .some(.some(let mailbox)) = stored, !options.contains(mailbox) { options.append(mailbox) }
        return Picker(NSLocalizedString("orchestrationPolicy.routing.label", comment: ""), selection: Binding(
            get: { selection },
            set: { value in
                let next: String?? = value == Self.inherit ? nil : value == Self.anyAgent ? .some(nil) : .some(value)
                onSave(override.withAssignTo(next))
            })) {
            Text(inheritLabel(labels.routing(inherited?.assignTo ?? nil))).tag(Self.inherit)
            Text(NSLocalizedString("orchestrationPolicy.routing.anyAgent", comment: "")).tag(Self.anyAgent)
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .accessibilityIdentifier("orchestration-\(scope.rawValue)-routing")
    }

    // MARK: Autonomy

    private func autonomyPicker(_ field: PolicyAutonomyField) -> some View {
        Picker(labels.action(field), selection: Binding(
            get: { override.autonomy(field)?.rawValue ?? Self.inherit },
            set: { onSave(override.withAutonomy(field, PolicyAutonomy(rawValue: $0))) })) {
            Text(inheritLabel(inherited?.autonomy(field).map(labels.autonomy) ?? "")).tag(Self.inherit)
            ForEach(PolicyAutonomy.allCases, id: \.self) { Text(labels.autonomy($0)).tag($0.rawValue) }
        }
        .accessibilityIdentifier("orchestration-\(scope.rawValue)-\(field.rawValue)")
    }

    // MARK: Escalation

    private var escalationPicker: some View {
        let stored = override.escalation
        let selection: String = switch stored {
        case .none: Self.inherit
        case .listOwner: "listOwner"
        case .taskCreator: "taskCreator"
        case .people(let ids): Self.person + (ids.first ?? "")
        }
        var people = labels.people.map { (id: $0.id, label: labels.person($0)) }
        if case .people(let ids)? = stored, let first = ids.first, !people.contains(where: { $0.id == first }) {
            people.append((id: first, label: labels.escalation(.people([first]))))
        }
        return Picker(NSLocalizedString("orchestrationPolicy.escalation.label", comment: ""), selection: Binding(
            get: { selection },
            set: { value in
                let next: PolicyEscalation? = value == Self.inherit ? nil
                    : value.hasPrefix(Self.person) ? .people([String(value.dropFirst(Self.person.count))])
                    : value == "taskCreator" ? .taskCreator : .listOwner
                onSave(override.withEscalation(next))
            })) {
            Text(inheritLabel(inherited?.escalation.map(labels.escalation) ?? "")).tag(Self.inherit)
            Text(labels.escalation(.listOwner)).tag("listOwner")
            Text(labels.escalation(.taskCreator)).tag("taskCreator")
            ForEach(people, id: \.id) { Text($0.label).tag(Self.person + $0.id) }
        }
        .accessibilityIdentifier("orchestration-\(scope.rawValue)-escalation")
    }
}

/// The trade-off policy (ADEV-281): a switch states one; then each threshold, and the goal order.
private struct OrchestrationTradeoffSection: View {
    let scope: OrchestrationPolicyScope
    let override: PolicyDocument
    let inherited: PolicyDocument?
    let goals: [ProjectGoal]
    let labels: OrchestrationPolicyLabels
    let disabled: Bool
    let inheritLabel: (String) -> String
    let onSave: (PolicyDocument?) -> Void

    @ThemedPalette private var palette

    private static let inherit = "__inherit"

    /// What an unset threshold takes: the inherited policy's, or the defaults where none is stated.
    private var fallback: PolicyDocument? {
        inherited?.tradeoffStated == true ? inherited : OrchestrationPolicyRules.tradeoffDefaults()
    }

    private var orderedGoals: [ProjectGoal] {
        let order = override.goalOrder ?? fallback?.goalOrder ?? []
        // A goal not saved yet has no id, and nothing to rank it by.
        let saved = goals.filter { $0.id != nil }
        let ranked = order.compactMap { id in saved.first { $0.id == id } }
        return ranked + saved.filter { !order.contains($0.id ?? "") }
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { override.tradeoffStated },
                                 set: { onSave(override.withTradeoffStated($0)) })) {
                VStack(alignment: .leading, spacing: Theme.spacing2) {
                    Text(NSLocalizedString("orchestrationPolicy.tradeoff.title", comment: ""))
                    Text(statusText)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(palette.textMuted)
                }
            }
            .accessibilityLabel(NSLocalizedString("orchestrationPolicy.tradeoff.switch", comment: ""))
            .accessibilityIdentifier("orchestration-\(scope.rawValue)-tradeoff-switch")

            if override.tradeoffStated {
                ForEach(PolicyTradeoffField.levels, id: \.self) { levelPicker($0) }
                ForEach(PolicyTradeoffField.probabilities, id: \.self) { probabilityPicker($0) }
                if orderedGoals.count > 1 { goalOrder }
            }
        } footer: {
            Text(NSLocalizedString("orchestrationPolicy.tradeoff.help", comment: ""))
        }
        .disabled(disabled)
    }

    private var statusText: String {
        let stated = NSLocalizedString("orchestrationPolicy.tradeoff.stated", comment: "")
        if override.tradeoffStated { return stated }
        if inherited?.tradeoffStated == true { return inheritLabel(stated) }
        return NSLocalizedString("orchestrationPolicy.tradeoff.none", comment: "")
    }

    private func fieldLabel(_ field: PolicyTradeoffField) -> String {
        NSLocalizedString("orchestrationPolicy.tradeoff.field.\(field.rawValue)", comment: "")
    }

    private func levelPicker(_ field: PolicyTradeoffField) -> some View {
        Picker(fieldLabel(field), selection: Binding(
            get: { override.level(field)?.rawValue ?? Self.inherit },
            set: { onSave(override.withLevel(field, PolicyLevel(rawValue: $0))) })) {
            Text(inheritLabel(fallback?.level(field).map(labels.level) ?? "")).tag(Self.inherit)
            ForEach(PolicyLevel.allCases, id: \.self) { Text(labels.level($0)).tag($0.rawValue) }
        }
        .accessibilityIdentifier("orchestration-\(scope.rawValue)-tradeoff-\(field.rawValue)")
    }

    private func probabilityPicker(_ field: PolicyTradeoffField) -> some View {
        let current = override.probability(field)
        let choices = Array(Set(PolicyTradeoffField.probabilityChoices + (current.map { [$0] } ?? []))).sorted()
        return Picker(fieldLabel(field), selection: Binding(
            get: { current.map { String($0) } ?? Self.inherit },
            set: { onSave(override.withProbability(field, $0 == Self.inherit ? nil : Double($0))) })) {
            Text(inheritLabel(fallback?.probability(field).map(labels.probability) ?? "")).tag(Self.inherit)
            ForEach(choices, id: \.self) { Text(labels.probability($0)).tag(String($0)) }
        }
        .accessibilityIdentifier("orchestration-\(scope.rawValue)-tradeoff-\(field.rawValue)")
    }

    private var goalOrder: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            HStack {
                Text(NSLocalizedString("orchestrationPolicy.tradeoff.goalOrder", comment: ""))
                Spacer()
                if override.goalOrder != nil {
                    Button(NSLocalizedString("orchestrationPolicy.tradeoff.goalOrderReset", comment: "")) {
                        onSave(override.withGoalOrder(nil))
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text(NSLocalizedString("orchestrationPolicy.tradeoff.goalOrderHelp", comment: ""))
                .font(Theme.Typography.caption1())
                .foregroundColor(palette.textMuted)
            ForEach(Array(orderedGoals.enumerated()), id: \.element.id) { index, goal in
                HStack {
                    Text(String(format: NSLocalizedString("orchestrationPolicy.tradeoff.goalRank", comment: ""), index + 1, goal.statement))
                        .lineLimit(1)
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0)
                        .accessibilityLabel(String(format: NSLocalizedString("orchestrationPolicy.tradeoff.moveUp", comment: ""), goal.statement))
                    Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == orderedGoals.count - 1)
                        .accessibilityLabel(String(format: NSLocalizedString("orchestrationPolicy.tradeoff.moveDown", comment: ""), goal.statement))
                }
                .buttonStyle(.borderless)
                .font(Theme.Typography.caption1())
            }
        }
        .accessibilityIdentifier("orchestration-\(scope.rawValue)-goal-order")
    }

    private func move(_ index: Int, by offset: Int) {
        var ids = orderedGoals.compactMap(\.id)
        let target = index + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        onSave(override.withGoalOrder(ids))
    }
}
