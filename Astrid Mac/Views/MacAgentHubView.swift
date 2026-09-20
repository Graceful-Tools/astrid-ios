//  MacAgentHubView.swift
//  Astrid for Mac — the Agent Hub (AITD-297), over the same `AgentHubModel` /
//  `WebhookSettingsModel` / `CustomAgentsModel` / `CopilotCloudAgentModel` as iOS. Replaces
//  MacAISettingsView + MacAIKeysView (Task f8687dfb): ownership first, transport under
//  "I run it", provider keys inline, Copilot OAuth, webhook editor, Custom Agents, the
//  assistant's model, and the GitHub App presented as server-run-only.

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacAgentHubView: View {
    @StateObject private var model = AgentHubModel()
    @StateObject private var capabilities = ServerCapabilityService.shared
    @State private var keyDrafts: [String: String] = [:]
    @State private var showWebhook = false
    @State private var showCustomAgents = false
    @State private var showCopilotCloud = false
    @State private var showConnections = false

    private var origin: String { Constants.API.baseURL }

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.agents.your_agents", comment: "")) {
                Text(String(format: NSLocalizedString("settings.agents.description", comment: ""), Brand.appName))
                    .font(.caption).foregroundStyle(Theme.textMuted)
                if capabilities.capabilities.integrations.mcp {
                    HStack {
                        if let guide = AgentHubLinks.loopsGuide(origin: origin) {
                            Button(NSLocalizedString("settings.agents.guide_link", comment: "")) { PlatformApplication.open(guide) }
                        }
                        if let download = AgentHubLinks.workflowDownload(origin: origin) {
                            Button(NSLocalizedString("settings.agents.download_skill", comment: "")) { PlatformApplication.open(download) }
                        }
                    }
                }
            }

            if model.isLoading {
                Section { ProgressView().controlSize(.small) }
            } else if let loadErrorMessage = model.loadErrorMessage {
                Section {
                    HStack {
                        Text(loadErrorMessage).foregroundStyle(Theme.error)
                        Spacer()
                        Button(NSLocalizedString("actions.retry", comment: "")) { _Concurrency.Task { await model.load() } }
                    }
                }
            } else {
                if let message = model.actionErrorMessage ?? model.setupErrorMessage {
                    Section { Text(message).font(.caption).foregroundStyle(Theme.error) }
                }
                ForEach(model.rows) { row in agentSection(row) }

                if capabilities.capabilities.integrations.customAgents {
                    Section(NSLocalizedString("settings.agents.custom.title", comment: "")) {
                        HStack {
                            Text(NSLocalizedString("settings.agents.custom.subtitle", comment: ""))
                                .font(.caption).foregroundStyle(Theme.textMuted)
                            Spacer()
                            Button(NSLocalizedString("mac.manage", comment: "")) { showCustomAgents = true }
                        }
                    }
                }

                Section(NSLocalizedString("settings.connections.title", comment: "")) {
                    HStack {
                        Text(NSLocalizedString("settings.connections.subtitle", comment: ""))
                            .font(.caption).foregroundStyle(Theme.textMuted)
                        Spacer()
                        Button(NSLocalizedString("mac.manage", comment: "")) { showConnections = true }
                    }
                }

                MacAssistantModelSection()
                GitHubConnectionSection()
            }
        }
        .formStyle(.grouped).macThemedSurface()
        .task { await model.load() }
        .sheet(isPresented: $showWebhook) {
            MacAgentHubSheet(title: WebhookSettingsScreen.title) { WebhookSettingsScreen() }
        }
        .sheet(isPresented: $showCustomAgents) {
            MacAgentHubSheet(title: CustomAgentsScreen.title, height: 520) { CustomAgentsScreen() }
        }
        .sheet(isPresented: $showCopilotCloud) {
            MacAgentHubSheet(title: CopilotCloudAgentScreen.title, height: 480) { CopilotCloudAgentScreen() }
        }
        .sheet(isPresented: $showConnections) {
            MacAgentHubSheet(title: ConnectionsScreen.title, height: 560) { ConnectionsScreen() }
        }
        // OAuth completes in the browser; re-poll on focus so a new Copilot grant shows up.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !model.isLoading else { return }
            _Concurrency.Task { await model.refreshCopilotStatus() }
        }
    }

    // MARK: - One provider row

    @ViewBuilder
    private func agentSection(_ row: AgentRuntimeRow) -> some View {
        let mode = model.mode(for: row)
        let ownership = mode.ownership

        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.label).foregroundStyle(Theme.textPrimary)
                        if !model.isConfigured(row) && mode != .off {
                            Text(NSLocalizedString("settings.agents.needs_setup", comment: ""))
                                .font(.caption).foregroundStyle(Theme.warning)
                        }
                    }
                    Text("\(row.identityMailbox(for: mode))@\(Brand.agentEmailDomain)")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if model.savingRowID == row.id { ProgressView().controlSize(.small) }
                Picker("", selection: Binding(
                    get: { ownership },
                    set: { newValue in _Concurrency.Task { await model.select(newValue, for: row) } }
                )) {
                    ForEach(AgentOwnership.allCases) { candidate in
                        Text(candidate.localizedLabel).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(model.savingRowID != nil)
            }

            if ownership == .user {
                Picker(NSLocalizedString("settings.agents.transport", comment: ""), selection: Binding(
                    get: { model.transport(for: row) ?? .polling },
                    set: { newValue in
                        if newValue == .sse {
                            showCustomAgents = true
                        } else {
                            _Concurrency.Task { await model.select(newValue, for: row) }
                        }
                    }
                )) {
                    ForEach(AgentSelfTransport.allCases) { transport in
                        Text(transport.localizedLabel).tag(transport)
                    }
                }
                .disabled(model.savingRowID != nil)
            }

            modeContent(mode, row: row)
        }
        .opacity(mode == .off ? 0.65 : 1)
    }

    @ViewBuilder
    private func modeContent(_ mode: AgentExecutionMode, row: AgentRuntimeRow) -> some View {
        switch mode {
        case .api:
            Text(String(format: NSLocalizedString("settings.agents.api_description", comment: ""), Brand.appName))
                .font(.caption).foregroundStyle(Theme.textMuted)
            if row.usesOAuth { copilotRow } else { keyRow(row) }
        case .polling:
            Text(String(format: NSLocalizedString("settings.agents.polling_description", comment: ""), row.label))
                .font(.caption).foregroundStyle(Theme.textMuted)
            Text(NSLocalizedString("settings.agents.polling_guide_hint", comment: ""))
                .font(.caption).foregroundStyle(Theme.textMuted)
            if row.usesOAuth && capabilities.capabilities.integrations.mcp {
                Button(NSLocalizedString("settings.agents.copilot_cloud.title", comment: "")) { showCopilotCloud = true }
            }
        case .webhook:
            Text(NSLocalizedString("settings.agents.webhook_description", comment: ""))
                .font(.caption).foregroundStyle(Theme.textMuted)
            Button(NSLocalizedString("settings.agents.webhook.configure", comment: "")) { showWebhook = true }
        case .off:
            Text(String(format: NSLocalizedString("settings.agents.off_description", comment: ""), Brand.appName))
                .font(.caption).foregroundStyle(Theme.textMuted)
        }
    }

    @ViewBuilder
    private var copilotRow: some View {
        HStack {
            Text(NSLocalizedString(
                model.copilotConnected ? "settings.agents.copilot_connected" : "settings.agents.copilot_disconnected",
                comment: ""
            )).font(.caption)
            Spacer()
            if model.isPollingCopilot {
                ProgressView().controlSize(.small)
            } else if model.copilotConnected {
                Button(NSLocalizedString("settings.agents.copilot_disconnect", comment: ""), role: .destructive) {
                    _Concurrency.Task { await model.disconnectCopilot() }
                }
            } else {
                Button(NSLocalizedString("settings.agents.copilot_connect", comment: "")) { connectCopilot() }
            }
        }
    }

    /// In-app auth session; the server callback ends on a "return to the app" page, so the
    /// session is closed by hand and the status polled afterwards.
    private func connectCopilot() {
        _Concurrency.Task {
            do {
                let url = try await model.copilotAuthorizationURL()
                _ = try? await OAuthWebConnector.shared.present(url: url, callbackScheme: "astrid")
                await model.pollCopilotStatus(maxAttempts: 10)
            } catch {
                model.setupErrorMessage = AgentHubErrors.message(error)
            }
        }
    }

    @ViewBuilder
    private func keyRow(_ row: AgentRuntimeRow) -> some View {
        let status = model.keyStatuses[row.service]
        let busy = model.keyOperationService == row.service
        HStack {
            Text(MacAIKeys.statusText(hasKey: status?.hasKey ?? false, preview: status?.keyPreview, isValid: status?.isValid))
                .font(.caption).foregroundStyle(Theme.textMuted)
            Spacer()
            if let docs = AIService(rawValue: row.service)?.documentationURL {
                Button(NSLocalizedString("settings.agents.get_key", comment: "")) { PlatformApplication.open(docs) }
                    .buttonStyle(.link)
            }
        }
        HStack {
            SecureField(
                status?.hasKey == true
                    ? NSLocalizedString("settings.agents.key_replace_placeholder", comment: "")
                    : (AIService(rawValue: row.service)?.keyPlaceholder ?? ""),
                text: Binding(get: { keyDrafts[row.service] ?? "" }, set: { keyDrafts[row.service] = $0 })
            )
            .textFieldStyle(.roundedBorder)
            Button(NSLocalizedString("actions.save", comment: "")) {
                let key = keyDrafts[row.service] ?? ""
                _Concurrency.Task {
                    await model.saveKey(key, for: row.service)
                    if model.actionErrorMessage == nil { keyDrafts[row.service] = "" }
                }
            }
            .disabled((keyDrafts[row.service] ?? "").isEmpty || busy)
            if status?.hasKey == true {
                Button(NSLocalizedString("settings.agents.test_key", comment: "")) {
                    _Concurrency.Task { await model.testKey(for: row.service) }
                }.disabled(busy)
                Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                    _Concurrency.Task { await model.deleteKey(for: row.service) }
                }.disabled(busy)
            }
            if busy { ProgressView().controlSize(.small) }
        }
        Text(NSLocalizedString("settings.agents.key_footer", comment: ""))
            .font(.caption).foregroundStyle(Theme.textMuted)
    }
}

// MARK: - The assistant's model (server-run only)

struct MacAssistantModelSection: View {
    @State private var settings: AIAssistantSettings?
    @State private var agents: [AvailableAgent] = []
    @State private var loadFailed = false
    @State private var isSaving = false

    var body: some View {
        Section(String(format: NSLocalizedString("settings.agents.model.title", comment: ""), Brand.appName)) {
            Text(String(format: NSLocalizedString("settings.agents.model.description", comment: ""), Brand.appName))
                .font(.caption).foregroundStyle(Theme.textMuted)
            if let s = settings {
                if agents.filter({ !$0.isDefaultAssistant }).isEmpty {
                    Text(String(format: NSLocalizedString("settings.agents.model.empty", comment: ""), Brand.appName, Brand.appName))
                        .font(.caption).foregroundStyle(Theme.warning)
                } else {
                    Picker(NSLocalizedString("settings.default_agent.title", comment: ""), selection: Binding(
                        get: { s.defaultAgentId ?? "" },
                        set: { newId in save(agentId: newId.isEmpty ? nil : newId) }
                    )) {
                        Text(NSLocalizedString("settings.default_agent.none", comment: "")).tag("")
                        ForEach(agents.filter { !$0.isDefaultAssistant }) { a in
                            Text("\(a.name) · \(a.serviceDisplayName)").tag(a.id)
                        }
                    }
                }
                if isSaving { ProgressView().controlSize(.small) }
            } else if loadFailed {
                HStack {
                    Text(NSLocalizedString("mac.ai_settings_load_failed", comment: "")).foregroundStyle(Theme.error)
                    Spacer()
                    Button(NSLocalizedString("actions.retry", comment: "")) { _Concurrency.Task { await load() } }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task { await load() }
    }

    private func load() async {
        loadFailed = false
        do {
            settings = try await ChatService.shared.getAIAssistantSettings()
            agents = (try? await ChatService.shared.fetchServerRunAgents()) ?? []
        } catch {
            loadFailed = true
        }
    }

    private func save(agentId: String?) {
        guard !isSaving else { return }
        isSaving = true
        _Concurrency.Task {
            defer { isSaving = false }
            if let updated = try? await ChatService.shared.updateAIAssistantSettings(defaultAgentId: agentId) {
                settings = updated
            }
        }
    }
}

// MARK: - One sheet chrome for every hub sub-screen (AITD-405)

/// The Mac presents the hub's sub-screens as sheets while iOS pushes them, so the Mac supplies a
/// header row, a `Done` button on ⏎ and a fixed size. That chrome used to be copy-pasted into each
/// of `MacWebhookSettingsView`, `MacCustomAgentsView` and `MacCopilotCloudAgentView`, which is what
/// made them twins of the iOS screens in the first place: the chrome was the only part that
/// differed, and it was written three times. Now it is written once, and the body inside it is the
/// shared screen from `Core/Platform/AgentHubScreens.swift`.
struct MacAgentHubSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var height: CGFloat = 560
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            content()
        }
        .frame(width: 520, height: height)
    }
}

#endif
