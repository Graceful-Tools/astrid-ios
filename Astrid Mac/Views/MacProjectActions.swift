//  MacProjectActions.swift
//  Astrid for Mac — deleting a project from the sidebar (ADEV-27). Creating one moved to
//  Settings ▸ Projects (ADEV-357, `ProjectsSettingsView`), shared with iPhone and iPad.
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

    /// The Projects section shows whenever Project Mode is on.
    static func showsSection(offered: Bool) -> Bool { offered }

    /// The name a new project is created with, or nil when there is nothing to create.
    static func projectName(from input: String) -> String? {
        ProjectsSettings.projectName(from: input)
    }

    /// The sidebar selection once `projectId` is gone: its board closes, anything else stays.
    static func selection(afterDeleting projectId: String, current: String?) -> String? {
        current == MacProjectSelection.tag(projectId: projectId) ? nil : current
    }

    /// The localized reason a delete was refused, or nil for any other failure.
    static func deleteRefusalKey(for error: Error) -> String? {
        ListProjectControl.deleteRefusalKey(for: error)
    }

    // MARK: - Doing it

    @MainActor
    static func delete(projectId: String, then done: @escaping () -> Void) {
        ListProjectControl.deleteProject(id: projectId, then: done)
    }
}
#endif
