//  MacListProjectControls.swift
//  Astrid for Mac — moving a list into and out of a project, and creating a list inside one
//  (AITD-681; core AITD-680 / D68, server AWTD-1702).
//
//  Jon, 2026-11-15: "How can I move lists into / out of projects or create a new list in a
//  project? Cannot figure it out." The only control was Create Board, which always makes a NEW
//  project. Every decision here is astrid-core's `listProjectMoves` (owner or admin of the list
//  AND of each project it touches; creating needs owner/admin/member of the project): this file
//  draws the answer and sends the core's commands, it never restates the rule.

#if os(macOS)
import AstridCore
import SwiftUI

/// The rule's translation and the commands are shared with iPhone/iPad (AITD-682):
/// `ListProjectControl` and `ListProjectMenu` in `Core/Lists/ListProjectControl.swift`.
typealias MacListProjectControl = ListProjectControl
typealias MacListProjectMenu = ListProjectMenu

// MARK: - List Settings ▸ Admin ▸ Project

struct MacListProjectRow: View {
    let list: TaskList
    @StateObject private var projectService = ProjectService.shared
    @StateObject private var listService = ListService.shared
    @State private var confirmingLeave = false

    var body: some View {
        let picker = MacListProjectControl.picker(
            list: list,
            moves: listService.projectMoves(listId: list.id),
            projects: projectService.projects,
            canEditSettings: ListPermissions.canEditSettings(list, userId: AuthManager.shared.userId))
        if MacListProjectControl.isOffered, picker.readOnly || !picker.options.isEmpty {
            HStack {
                Text(NSLocalizedString("projects.project", comment: ""))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if picker.readOnly {
                    Text(label(picker.current)).foregroundStyle(Theme.textSecondary)
                } else {
                    SwiftUI.Picker("", selection: Binding(
                        get: { picker.current },
                        set: { choose($0, current: picker.current) })) {
                        ForEach(picker.options, id: \.self) { option in
                            Text(label(option)).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("listSettings.project")
                }
            }
            .padding(.horizontal, 4)
            .confirmationDialog(
                String(format: NSLocalizedString("projects.leave_confirm", comment: ""),
                       list.name, label(picker.current)),
                isPresented: $confirmingLeave) {
                Button(NSLocalizedString("projects.remove_from", comment: ""), role: .destructive) {
                    MacListProjectControl.move(listId: list.id, to: nil)
                }
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("projects.leave_confirm_detail", comment: ""))
            }
        }
    }

    private func label(_ option: MacListProjectControl.Option) -> String {
        switch option {
        case .none: return NSLocalizedString("projects.none", comment: "")
        case let .project(_, name): return name
        case .newProject: return NSLocalizedString("projects.new_project", comment: "")
        }
    }

    private func choose(_ option: MacListProjectControl.Option, current: MacListProjectControl.Option) {
        switch MacListProjectControl.action(choosing: option, current: current) {
        case .nothing: break
        case let .move(projectId): MacListProjectControl.move(listId: list.id, to: projectId)
        case .confirmLeave: confirmingLeave = true
        case .createProject:
            let list = list
            AppActions.perform("Create board") {
                _ = try await ProjectService.shared.createBoardForList(list)
            }
        }
    }
}

// MARK: - New List in Project…

struct MacNewListInProjectSheet: View {
    let project: Project
    var onCreated: (TaskList) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AstridTokens.Space.s12) {
            Text(String(format: NSLocalizedString("projects.new_list_in_title", comment: ""), project.name))
                .macFont(.headline).foregroundStyle(Theme.textPrimary)
            TextField(NSLocalizedString("lists.list_name", comment: ""), text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("projects.newListName")
                .onSubmit(create)
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("actions.create", comment: ""), action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
                    .accessibilityIdentifier("projects.newListCreate")
            }
        }
        .padding(AstridTokens.Space.s20)
        .frame(minWidth: 320)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        guard !trimmed.isEmpty else { return }
        MacListProjectControl.createList(named: trimmed, in: project.id, then: onCreated)
        dismiss()
    }
}
#endif
