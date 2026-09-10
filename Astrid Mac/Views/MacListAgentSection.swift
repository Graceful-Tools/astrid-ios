//  MacListAgentSection.swift
//  Astrid for Mac — which AI model answers in ONE list (AITD-380).
//
//  Mac had nothing for this. `MacListMembersView` DISPLAYS agents that are already members, and
//  that was the whole of it — so an agent added on the web was visible here and unconfigurable.
//  iOS looked like it had the screen (`ListAgentSettingsView`), but that view is unreachable and
//  its save builds an EMPTY request: `UpdateListRequest` had no agent field at all, so the
//  checkmark moved and nothing persisted. Porting it would have shipped the same silence to Mac.
//
//  A section inside `MacListEditSheet` rather than a new `MacListMenu` item: `.edit` is already
//  in that menu, already gated on `ListPermissions.canEditSettings`, and already drawn by both
//  the sidebar right-click and the board's strip. A second door to list settings would be one
//  more thing to keep in step for no new reach. Web puts it in the same place.
//
//  The shape follows `MacAgentHubView`'s account-level picker — same roster call, same
//  "account default" row — because this is that setting scoped to a list, and the two should not
//  look like different features.

#if os(macOS)
import SwiftUI

struct MacListAgentSection: View {
    let list: TaskList

    @State private var agents: [AvailableAgent] = []
    @State private var selectedAgentId: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saveFailed = false

    /// The SHARED rule, asked and never restated (ASTRID.md §0 rule 8) — the permission matrix is
    /// a cross-platform contract with Web, and `ListPermissionsTests` fails on hand-rolled forms.
    private var canEdit: Bool {
        ListPermissions.canEditSettings(list, userId: AuthManager.shared.userId)
    }

    /// The default assistant identity is not a *choice* of model — it is what "account default"
    /// already means — so it is filtered out here exactly as the account-level picker filters it.
    private var choosableAgents: [AvailableAgent] {
        agents.filter { !$0.isDefaultAssistant }
    }

    var body: some View {
        if canEdit {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("lists.ai_agent.section", comment: ""))
                    .font(.caption).foregroundStyle(Theme.textSecondary)

                if isLoading {
                    ProgressView().controlSize(.small)
                } else if choosableAgents.isEmpty {
                    // Server-run, so it needs a keyed agent. Nothing to choose between is a
                    // reason to say so, not to draw an empty picker.
                    Text(String(format: NSLocalizedString("settings.agents.model.empty", comment: ""),
                                Brand.appName, Brand.appName))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                } else {
                    picker
                    Text(String(format: NSLocalizedString("lists.ai_agent.footer", comment: ""),
                                Brand.appName))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }

                if saveFailed {
                    Text(NSLocalizedString("mac.failed.save", comment: ""))
                        .font(.caption).foregroundStyle(Theme.error)
                }
            }
            .task { await load() }
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            Picker(String(format: NSLocalizedString("lists.ai_agent.model", comment: ""), Brand.appName),
                   selection: Binding(
                       get: { selectedAgentId ?? "" },
                       set: { save(agentId: $0.isEmpty ? nil : $0) }
                   )) {
                Text(NSLocalizedString("lists.ai_agent.account_default", comment: "")).tag("")
                ForEach(choosableAgents) { agent in
                    Text("\(agent.name) · \(agent.serviceDisplayName)").tag(agent.id)
                }
            }
            .accessibilityIdentifier("listEdit.aiAgent")
            if isSaving { ProgressView().controlSize(.small) }
        }
    }

    private func load() async {
        // The list is the authority on what is currently chosen — read through the shared
        // accessor so Mac and iOS agree on what an empty id means.
        selectedAgentId = ListAgentSettings.currentDefaultAgentId(on: list)
        agents = (try? await ChatService.shared.fetchServerRunAgents()) ?? []
        isLoading = false
    }

    private func save(agentId: String?) {
        guard !isSaving else { return }
        let previous = selectedAgentId
        selectedAgentId = agentId          // optimistic: the picker must not lag the click
        isSaving = true
        saveFailed = false

        _Concurrency.Task {
            defer { isSaving = false }
            do {
                // Through the service, never AstridAPIClient (ASTRID.md §0 rule 1). It builds the
                // body with ListAgentSettings, which carries the list's enabled types forward —
                // aiAgentConfig REPLACES the stored config, so a naive write erases them.
                _ = try await ListService.shared.setListDefaultAgent(listId: list.id, agentId: agentId)
            } catch {
                selectedAgentId = previous
                saveFailed = true
            }
        }
    }
}
#endif
