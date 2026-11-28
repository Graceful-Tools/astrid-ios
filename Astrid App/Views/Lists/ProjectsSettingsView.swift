//  ProjectsSettingsView.swift
//  Settings ▸ Projects (ADEV-357): make a project, and edit or delete the ones you may. Shared by
//  iPhone, iPad and Mac — a row in iOS Settings, a tab in the Mac's Settings window.
//
//  Edit opens the same `EditProjectSheet` the sidebar's right-click does (name, description,
//  colour, goals and guardrails). What each row offers is `ProjectsSettings.rows`.

import SwiftUI

struct ProjectsSettingsView: View {
    @StateObject private var projectService = ProjectService.shared
    @ThemedPalette private var palette
    @State private var creating = false
    @State private var newName = ""
    @State private var editing: Project?
    @State private var deleting: Project?

    private var rows: [ProjectsSettings.Row] {
        ProjectsSettings.rows(projects: projectService.projects, userId: AuthManager.shared.userId,
                              offered: ListProjectControl.isOffered)
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    projectRow(row)
                }
                Button {
                    newName = ""
                    creating = true
                } label: {
                    Label(NSLocalizedString("projects.new_project", comment: ""), systemImage: "plus")
                }
                .accessibilityIdentifier("settings.projects.new")
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .navigationTitle(NSLocalizedString("project_mode.projects_heading", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await projectService.reload() }
        .alert(NSLocalizedString("projects.new_project_title", comment: ""), isPresented: $creating) {
            TextField(NSLocalizedString("projects.project_name", comment: ""), text: $newName)
                .accessibilityIdentifier("settings.projects.newName")
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("actions.create", comment: "")) {
                if let name = ProjectsSettings.projectName(from: newName) { ProjectsSettings.create(named: name) }
            }
        }
        .sheet(item: $editing) { project in
            EditProjectSheet(project: project)
        }
        .confirmationDialog(
            String(format: NSLocalizedString("projects.delete_confirm", comment: ""), deleting?.name ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting) { project in
            Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                ListProjectControl.deleteProject(id: project.id) {}
            }
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
        } message: { _ in
            Text(NSLocalizedString("projects.delete_confirm_detail", comment: ""))
        }
    }

    private func projectRow(_ row: ProjectsSettings.Row) -> some View {
        HStack(spacing: Theme.spacing8) {
            Text(verbatim: row.name)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.spacing8)
            if row.canEdit {
                Button(NSLocalizedString("projects.edit_project", comment: "")) { editing = row.project }
                    .accessibilityIdentifier("settings.projects.edit")
            }
            if row.canDelete {
                Button(role: .destructive) { deleting = row.project } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(NSLocalizedString("projects.delete_project", comment: ""))
                .accessibilityIdentifier("settings.projects.delete")
            }
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.projects.row")
    }
}
