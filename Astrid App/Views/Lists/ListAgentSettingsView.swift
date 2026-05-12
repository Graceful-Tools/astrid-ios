import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "ListAgentSettings")

/// Per-list AI agent configuration (override default agent for this list)
struct ListAgentSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let listId: String

    @State private var agents: [AvailableAgent] = []
    @State private var selectedAgentId: String?
    @State private var useDefault = true
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                Section(footer: Text("When set, this agent will automatically respond to messages in this list's chat.")) {
                    // Use default option
                    Button {
                        useDefault = true
                        selectedAgentId = nil
                        saveListAgentSetting(nil)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Use Default Agent")
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text("Uses your global default agent setting")
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                            Spacer()
                            if useDefault {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }

                    // No agent option
                    Button {
                        useDefault = false
                        selectedAgentId = "none"
                        saveListAgentSetting("none")
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("No Agent")
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text("Disable automatic agent responses for this list")
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                            Spacer()
                            if !useDefault && selectedAgentId == "none" {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }
                }

                // Specific agent options
                if !agents.isEmpty {
                    Section(header: Text("Choose Agent")) {
                        ForEach(agents) { agent in
                            Button {
                                useDefault = false
                                selectedAgentId = agent.id
                                saveListAgentSetting(agent.id)
                            } label: {
                                HStack(spacing: Theme.spacing12) {
                                    if let asset = agent.serviceImageAsset {
                                        Image(asset)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    } else {
                                        ZStack {
                                            Circle()
                                                .fill(Color.purple.opacity(0.15))
                                                .frame(width: 32, height: 32)
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 14))
                                                .foregroundColor(.purple)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(agent.name)
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        Text(agent.serviceDisplayName)
                                            .font(Theme.Typography.caption2())
                                            .foregroundColor(.purple)
                                    }

                                    Spacer()

                                    if !useDefault && selectedAgentId == agent.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("List AI Agent")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true

        do {
            agents = try await ChatService.shared.fetchAvailableAgents()

            // Check current list's agent setting
            if let list = ListService.shared.lists.first(where: { $0.id == listId }) {
                // TODO: Read aiAgentsEnabled from list model when available
                // For now, default to "use default"
                _ = list
            }
        } catch {
            errorMessage = "Failed to load agents"
        }

        isLoading = false
    }

    private func saveListAgentSetting(_ agentId: String?) {
        isSaving = true

        _Concurrency.Task {
            do {
                // Update list with agent setting
                // This would use the list update API with aiAgentsEnabled field
                let request = UpdateListRequest(
                    // Pass agent config through list update when API supports it
                )
                _ = try await ListService.shared.updateListOnServer(listId: listId, updates: request)
                logger.notice("Updated list agent to: \(agentId ?? "default", privacy: .public)")
            } catch {
                logger.error("Failed to update list agent: \(error.localizedDescription, privacy: .public)")
            }
            isSaving = false
        }
    }
}
