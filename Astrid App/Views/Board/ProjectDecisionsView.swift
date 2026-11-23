//  ProjectDecisionsView.swift
//  ADEV-189 (web ADEV-180): a project's decisions. The list shows the open ones first, each decided
//  one with the option chosen, and starts a new one from the project's goals. A decision opens to
//  its options, so the choice is recorded with a tap, and to its trade-off grid, edited cell by cell
//  and saved back into the task's description (`DecisionGrid`). There is no score column: the
//  person decides (web ADEV-178).

import AstridCore
import SwiftUI

struct ProjectDecisionsView: View {
    let projectId: String

    @StateObject private var service = ProjectDecisionsService.shared
    @ThemedPalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var loadFailed = false
    @State private var creating = false
    @State private var newTitle = ""
    @State private var showNewPrompt = false
    @State private var path: [String] = []
    @State private var createFailed = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(NSLocalizedString("project_decisions.title", comment: "Decisions"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            newTitle = ""
                            showNewPrompt = true
                        } label: {
                            Label(NSLocalizedString("project_decisions.new", comment: "New decision"),
                                  systemImage: "plus")
                        }
                        .disabled(creating)
                        .accessibilityIdentifier("projectDecisions.new")
                    }
                }
                .navigationDestination(for: String.self) { decisionId in
                    ProjectDecisionDetailView(projectId: projectId, decisionId: decisionId)
                }
                .alert(NSLocalizedString("project_decisions.new", comment: ""), isPresented: $showNewPrompt) {
                    TextField(NSLocalizedString("project_decisions.new_placeholder", comment: ""), text: $newTitle)
                    Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
                    Button(NSLocalizedString("actions.create", comment: "")) { create() }
                } message: {
                    Text(NSLocalizedString("project_decisions.new_hint", comment: ""))
                }
                .alert(NSLocalizedString("project_decisions.create_failed", comment: ""), isPresented: $createFailed) {
                    Button(NSLocalizedString("actions.done", comment: ""), role: .cancel) {}
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        let decisions = service.decisions(projectId: projectId)
        if let decisions, !decisions.isEmpty {
            List {
                let open = decisions.filter { !$0.isDecided }
                let decided = decisions.filter(\.isDecided)
                if !open.isEmpty {
                    Section(NSLocalizedString("project_decisions.open", comment: "Open")) {
                        ForEach(open) { row($0) }
                    }
                }
                if !decided.isEmpty {
                    Section(NSLocalizedString("project_decisions.decided", comment: "Decided")) {
                        ForEach(decided) { row($0) }
                    }
                }
            }
            .refreshable { await load() }
            .accessibilityIdentifier("projectDecisions.list")
        } else if decisions == nil && (loading || !loadFailed) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Theme.spacing8) {
                Text(NSLocalizedString(loadFailed && decisions == nil ? "project_decisions.load_failed"
                                                                      : "project_decisions.empty", comment: ""))
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.spacing24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("projectDecisions.empty")
        }
    }

    private func row(_ decision: ProjectDecision) -> some View {
        NavigationLink(value: decision.id) {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(verbatim: decision.prompt.isEmpty ? decision.title : decision.prompt)
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textPrimary)
                if let chosen = decision.chosen {
                    Text(verbatim: Self.chosenText(chosen))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(palette.textSecondary)
                }
            }
        }
    }

    /// "Chose 2 — Option 2".
    static func chosenText(_ chosen: ProjectDecision.Chosen) -> String {
        let option = chosen.text.isEmpty ? "\(chosen.number)" : "\(chosen.number) — \(chosen.text)"
        return String(format: NSLocalizedString("project_decisions.chosen", comment: "Chose %@"), option)
    }

    private func load() async {
        loading = true
        loadFailed = !(await service.load(projectId: projectId))
        loading = false
    }

    private func create() {
        creating = true
        _Concurrency.Task {
            let id = await service.create(projectId: projectId, title: newTitle)
            creating = false
            if let id {
                // The new task reaches the local cache by sync; open it straight away regardless.
                path.append(id)
            } else {
                createFailed = true
            }
        }
    }
}

/// One decision: its question, an option to tap for the choice, and its grid.
struct ProjectDecisionDetailView: View {
    let projectId: String
    let decisionId: String

    @StateObject private var service = ProjectDecisionsService.shared
    @StateObject private var taskService = TaskService.shared
    @ThemedPalette private var palette
    @State private var deciding = false
    @State private var decideFailed = false
    @State private var editingGrid = false

    private var decision: ProjectDecision? {
        service.decisions(projectId: projectId)?.first { $0.id == decisionId }
    }

    private var task: Task? { taskService.tasksById[decisionId] }

    var body: some View {
        List {
            if let decision {
                Section {
                    Text(verbatim: decision.prompt.isEmpty ? decision.title : decision.prompt)
                        .font(Theme.Typography.headline())
                        .foregroundColor(palette.textPrimary)
                }
                Section(NSLocalizedString("project_decisions.options", comment: "Options")) {
                    ForEach(decision.options, id: \.number) { option in
                        optionRow(option, decision: decision)
                    }
                }
            }
            Section {
                if let task, DecisionGrid.parse(task.description) != nil {
                    Button(NSLocalizedString("project_decisions.edit_grid", comment: "Edit trade-offs")) {
                        editingGrid = true
                    }
                    .accessibilityIdentifier("projectDecisions.editGrid")
                }
                if let task {
                    Button(NSLocalizedString("project_decisions.open_task", comment: "Open task")) {
                        TaskPresenter.shared.showTask(task)
                    }
                } else {
                    Button(NSLocalizedString("project_decisions.open_task", comment: "Open task")) {
                        TaskPresenter.shared.showTask(taskId: decisionId)
                    }
                }
            }
        }
        .navigationTitle(decision?.title ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $editingGrid) {
            if let task { DecisionGridEditor(task: task) }
        }
        .alert(NSLocalizedString("project_decisions.decide_failed", comment: ""), isPresented: $decideFailed) {
            Button(NSLocalizedString("actions.done", comment: ""), role: .cancel) {}
        }
        .task {
            if decision == nil { await service.load(projectId: projectId) }
        }
    }

    private func optionRow(_ option: ProjectDecision.Option, decision: ProjectDecision) -> some View {
        let chosen = decision.chosen?.number == option.number
        return Button {
            decide(option.number)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing8) {
                Text(verbatim: "\(option.number).")
                    .font(Theme.Typography.body().monospacedDigit())
                    .foregroundColor(palette.textSecondary)
                VStack(alignment: .leading, spacing: Theme.spacing2) {
                    Text(verbatim: option.text).foregroundColor(palette.textPrimary)
                    if option.recommended {
                        Text(NSLocalizedString("project_decisions.recommended", comment: "Recommended"))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(palette.textSecondary)
                    }
                }
                Spacer(minLength: Theme.spacing8)
                if chosen {
                    Image(systemName: "checkmark").foregroundColor(palette.textPrimary)
                        .accessibilityLabel(NSLocalizedString("project_decisions.chosen_mark", comment: "Chosen"))
                }
            }
            .font(Theme.Typography.body())
        }
        .disabled(deciding || chosen)
        .accessibilityIdentifier("projectDecisions.option.\(option.number)")
    }

    private func decide(_ number: Int) {
        deciding = true
        _Concurrency.Task {
            decideFailed = !(await service.decide(projectId: projectId, decisionId: decisionId, option: number))
            deciding = false
        }
    }
}

/// The grid of one decision, cell by cell: a rating and its reason for each option and criterion.
/// Saving writes the grid back where it was in the description; the prose around it is untouched.
struct DecisionGridEditor: View {
    let task: Task

    @Environment(\.dismiss) private var dismiss
    @ThemedPalette private var palette
    @State private var grid: DecisionGrid
    @State private var saving = false
    @State private var saveFailed = false

    init(task: Task) {
        self.task = task
        _grid = State(initialValue: DecisionGrid.parse(task.description)?.grid
                      ?? DecisionGrid(optionLabel: "", criteria: [], options: []))
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(grid.options.indices, id: \.self) { o in
                    Section {
                        TextField(NSLocalizedString("project_decisions.option_name", comment: ""),
                                  text: $grid.options[o].name)
                            .font(Theme.Typography.headline())
                        ForEach(grid.criteria.indices, id: \.self) { c in
                            cellEditor(option: o, criterion: c)
                        }
                    } header: {
                        Text(verbatim: "\(o + 1)")
                    }
                }
                Section {
                    Text(NSLocalizedString("project_decisions.no_score_hint", comment: ""))
                        .font(Theme.Typography.footnote())
                        .foregroundColor(palette.textSecondary)
                }
            }
            .navigationTitle(NSLocalizedString("project_decisions.edit_grid", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.save", comment: "")) { save() }
                        .disabled(saving)
                        .accessibilityIdentifier("projectDecisions.saveGrid")
                }
            }
            .alert(NSLocalizedString("project_decisions.save_failed", comment: ""), isPresented: $saveFailed) {
                Button(NSLocalizedString("actions.done", comment: ""), role: .cancel) {}
            }
        }
    }

    private func cellEditor(option o: Int, criterion c: Int) -> some View {
        let cell = Binding<DecisionGrid.Cell>(
            get: { c < grid.options[o].cells.count ? grid.options[o].cells[c] : .init(rating: nil, text: "") },
            set: { value in
                while grid.options[o].cells.count <= c { grid.options[o].cells.append(.init(rating: nil, text: "")) }
                grid.options[o].cells[c] = value
            })
        return VStack(alignment: .leading, spacing: Theme.spacing4) {
            Picker(selection: Binding(get: { cell.wrappedValue.rating ?? "" },
                                      set: { cell.wrappedValue.rating = $0.isEmpty ? nil : $0 })) {
                Text(TradeOffPalette.label(for: nil)).tag("")
                ForEach(Self.tokens(keeping: cell.wrappedValue.rating), id: \.self) { token in
                    Text(verbatim: "\(token)  \(TradeOffPalette.label(for: Self.rating(token)))").tag(token)
                }
            } label: {
                Text(verbatim: grid.criteria[c]).foregroundColor(palette.textPrimary)
            }
            TextField(NSLocalizedString("project_decisions.reason_placeholder", comment: ""),
                      text: Binding(get: { cell.wrappedValue.text }, set: { cell.wrappedValue.text = $0 }))
                .font(Theme.Typography.callout())
                .foregroundColor(palette.textSecondary)
        }
    }

    /// The picker's tokens, plus the cell's own if it was written as an emoji, so it is kept.
    static func tokens(keeping current: String?) -> [String] {
        let plain = DecisionGrid.ratingTokens
        guard let current, !current.isEmpty, !plain.contains(current) else { return plain }
        return plain + [current]
    }

    static func rating(_ token: String) -> TradeOffRating? {
        DecisionGrid.rank(of: token).flatMap(TradeOffRating.init(rawValue:))
    }

    private func save() {
        guard let description = DecisionGrid.replace(in: task.description, with: grid) else {
            saveFailed = true
            return
        }
        saving = true
        _Concurrency.Task {
            do {
                _ = try await TaskService.shared.updateTask(taskId: task.id, description: description, task: task)
                dismiss()
            } catch {
                saveFailed = true
            }
            saving = false
        }
    }
}
