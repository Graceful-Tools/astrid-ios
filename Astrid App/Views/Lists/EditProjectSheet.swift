//  EditProjectSheet.swift
//  ADEV-65: rename or edit a project from its sidebar header, on iPhone, iPad and Mac.
//
//  Jon, 2026-11-17: "long press on project title in left side list should allow delete or rename
//  project or edit". Delete was already there (ADEV-46/27); a project's name could not be changed
//  anywhere until web's PATCH /api/v1/projects/:id took name, description and colour (ADEV-67)
//  and core grew `updateProject` (ADEV-69). Who may edit is the server's bar, owner or project
//  admin: `ListProjectControl.offersEdit` draws the actions, a refusal is named.

import SwiftUI

// Shared with the Mac target.

/// Edit Project…: the name, description and colour, saved together as one edit — and, for whoever
/// the server lets edit them, the project's goals and guardrails (ADEV-183), PUT as a whole.
struct EditProjectSheet: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var color: String
    @FocusState private var nameFocused: Bool
    @StateObject private var goalsService = ProjectGoalsService.shared
    /// The goals being edited, and what they were when read; nil until read, or when this person
    /// may not edit them.
    @State private var goalsDraft: ProjectGoalsDraft?
    @State private var goalsLoaded: ProjectGoalsDraft?
    @State private var goalsSaveFailed = false
    @State private var saving = false

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _description = State(initialValue: project.description ?? "")
        _color = State(initialValue: project.color ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(NSLocalizedString("projects.project_name", comment: ""), text: $name)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .accessibilityIdentifier("projects.editName")
                TextField(NSLocalizedString("projects.description", comment: ""), text: $description,
                          axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("projects.editDescription")
                Section(NSLocalizedString("projects.color", comment: "")) {
                    ListColorSwatches(color: color) { color = $0 }
                }
                if let draft = goalsDraft {
                    ProjectGoalsEditor(draft: Binding(get: { draft }, set: { goalsDraft = $0 }), projectId: project.id)
                }
                if goalsSaveFailed {
                    Text(NSLocalizedString("project_goals.save_failed", comment: ""))
                        .foregroundStyle(Theme.errorInk)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(NSLocalizedString("projects.edit_title", comment: ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.save", comment: ""), action: save)
                        .disabled((edit == nil && !goalsChanged) || saving)
                        .accessibilityIdentifier("projects.editSave")
                }
            }
            .onAppear { nameFocused = true }
            .task(id: project.id) { await loadGoals() }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }

    private var edit: ProjectEdit? {
        ListProjectControl.edit(of: project, name: name, description: description, color: color)
    }

    private var goalsChanged: Bool { goalsDraft != nil && goalsDraft != goalsLoaded }

    private func loadGoals() async {
        await goalsService.load(projectId: project.id)
        guard goalsDraft == nil, let goals = goalsService.goals(projectId: project.id), goals.canEdit else { return }
        let draft = ProjectGoalsDraft(goals)
        goalsDraft = draft
        goalsLoaded = draft
    }

    private func save() {
        if let edit { ListProjectControl.updateProject(id: project.id, edit: edit) }
        guard goalsChanged, let update = goalsDraft?.update else { return dismiss() }
        // The goals are online only: stay open and say so if the server refuses them.
        saving = true
        goalsSaveFailed = false
        _Concurrency.Task {
            let saved = await goalsService.save(projectId: project.id, update)
            saving = false
            if saved { dismiss() } else { goalsSaveFailed = true }
        }
    }
}

/// Rename Project…: the name alone, in an alert, beside Delete in the header's menu.
struct RenameProjectAlert: ViewModifier {
    @Binding var renaming: Project?
    let project: Project
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert(
            String(format: NSLocalizedString("projects.rename_title", comment: ""), project.name),
            isPresented: Binding(get: { renaming?.id == project.id },
                                 set: { if !$0 { renaming = nil } })) {
            TextField(NSLocalizedString("projects.project_name", comment: ""), text: $name)
                .accessibilityIdentifier("projects.renameName")
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("actions.save", comment: "")) {
                if let edit = ListProjectControl.edit(of: project, name: name,
                                                      description: project.description ?? "",
                                                      color: project.color ?? "") {
                    ListProjectControl.updateProject(id: project.id, edit: edit)
                }
            }
            .accessibilityIdentifier("projects.renameSave")
        }
        .onChange(of: renaming?.id == project.id) { _, presented in
            if presented { name = project.name }
        }
    }
}

extension View {
    func renameProjectAlert(_ renaming: Binding<Project?>, for project: Project) -> some View {
        modifier(RenameProjectAlert(renaming: renaming, project: project))
    }
}
