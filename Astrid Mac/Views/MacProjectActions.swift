//  MacProjectActions.swift
//  Astrid for Mac — creating a project on its own and deleting one (ADEV-27).
//
//  Jon, 2026-11-16: the Mac "can't create, edit (add/remove lists, users), delete projects". Lists
//  already move in and out (AITD-681) and a board's rows are its Add list / × (AITD-674); what had
//  no door was a project itself. The sidebar's Projects section hid until a project existed, so
//  there was nowhere to start one, and Delete lived only behind a list's Settings ▸ board switch.
//  Who may delete is the server's rule (owner only, as on web): a refusal is named, not guessed.

#if os(macOS)
import AstridCore
import SwiftUI

enum MacProjectActions {

    /// The Projects section shows whenever Project Mode is on — with no projects it is where the
    /// first one is made.
    static func showsSection(offered: Bool) -> Bool { offered }

    /// The name a new project is created with, or nil when there is nothing to create.
    static func projectName(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The sidebar selection once `projectId` is gone: its board closes, anything else stays.
    static func selection(afterDeleting projectId: String, current: String?) -> String? {
        current == MacProjectSelection.tag(projectId: projectId) ? nil : current
    }

    /// The localized reason a delete was refused, or nil for any other failure.
    static func deleteRefusalKey(for error: Error) -> String? {
        (error as? CoreFailure)?.status == 403 ? "projects.delete_forbidden" : nil
    }

    // MARK: - Doing it

    @MainActor
    static func create(named name: String, then done: @escaping (Project) -> Void) {
        _Concurrency.Task {
            do {
                done(try await ProjectService.shared.createProject(name: name))
            } catch {
                if let key = MacListProjectControl.refusalKey(for: error) {
                    AppErrorCenter.shared.show(NSLocalizedString(key, comment: ""))
                } else {
                    AppErrorCenter.shared.report("Create project", error)
                }
            }
        }
    }

    @MainActor
    static func delete(projectId: String, then done: @escaping () -> Void) {
        _Concurrency.Task {
            do {
                _ = try await ProjectService.shared.deleteProject(id: projectId)
                done()
            } catch {
                if let key = deleteRefusalKey(for: error) {
                    AppErrorCenter.shared.show(NSLocalizedString(key, comment: ""))
                } else {
                    AppErrorCenter.shared.report("Delete project", error)
                }
            }
        }
    }
}

// MARK: - New Project…

struct MacNewProjectSheet: View {
    var onCreated: (Project) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AstridTokens.Space.s12) {
            Text(NSLocalizedString("projects.new_project_title", comment: ""))
                .macFont(.headline).foregroundStyle(Theme.textPrimary)
            TextField(NSLocalizedString("projects.project_name", comment: ""), text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("projects.newProjectName")
                .onSubmit(create)
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("actions.create", comment: ""), action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(MacProjectActions.projectName(from: name) == nil)
                    .accessibilityIdentifier("projects.newProjectCreate")
            }
        }
        .padding(AstridTokens.Space.s20)
        .frame(minWidth: 320)
    }

    private func create() {
        guard let name = MacProjectActions.projectName(from: name) else { return }
        MacProjectActions.create(named: name, then: onCreated)
        dismiss()
    }
}
#endif
