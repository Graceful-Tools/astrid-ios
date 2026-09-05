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

                MacAssistantModelSection()
                MacGitHubConnectionSection()
            }
        }
        .formStyle(.grouped).macThemedSurface()
        .task { await model.load() }
        .sheet(isPresented: $showWebhook) { MacWebhookSettingsView() }
        .sheet(isPresented: $showCustomAgents) { MacCustomAgentsView() }
        .sheet(isPresented: $showCopilotCloud) { MacCopilotCloudAgentView() }
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

// MARK: - GitHub App connection (server-run only, managed on the web)

struct MacGitHubConnectionSection: View {
    @State private var status: GitHubStatusResponse?
    @State private var failed = false

    var body: some View {
        Section(NSLocalizedString("settings.agents.github.title", comment: "")) {
            Text(String(format: NSLocalizedString("settings.agents.github.description", comment: ""), Brand.appName))
                .font(.caption).foregroundStyle(Theme.textMuted)
            HStack {
                Circle().fill(status?.isGitHubConnected == true ? Theme.success : Theme.textMuted).frame(width: 8, height: 8)
                if let status {
                    Text(NSLocalizedString(
                        status.isGitHubConnected ? "settings.agents.github.connected" : "settings.agents.github.not_connected",
                        comment: ""
                    )).foregroundStyle(Theme.textPrimary)
                    if status.isGitHubConnected {
                        Text(String(format: NSLocalizedString("settings.agents.github.repositories", comment: ""), status.repositoryCount))
                            .font(.caption).foregroundStyle(Theme.textMuted)
                    }
                } else if failed {
                    Text(NSLocalizedString("settings.agents.github.not_connected", comment: "")).foregroundStyle(Theme.textPrimary)
                } else {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let url = AgentHubLinks.webAgentSettings(origin: Constants.API.baseURL) {
                    Button(NSLocalizedString("settings.agents.github.manage", comment: "")) { PlatformApplication.open(url) }
                }
            }
        }
        .task {
            do { status = try await RemoteResourceService.shared.getGitHubStatus() } catch { failed = true }
        }
    }
}

// MARK: - Webhook transport sheet

struct MacWebhookSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebhookSettingsModel()
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("settings.agents.transport.webhook", comment: "")).font(.headline)
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            Form {
                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage).font(.caption).foregroundStyle(Theme.error)
                        if model.requiresWebSession { MacWebSessionRequiredRow() }
                    }
                }
                if let secret = model.newSecret {
                    Section(NSLocalizedString("settings.agents.webhook.secret_title", comment: "")) {
                        Text(NSLocalizedString("settings.agents.webhook.secret_warning", comment: ""))
                            .font(.caption).foregroundStyle(Theme.warning)
                        MacCopyableCode(code: secret)
                    }
                }
                Section {
                    TextField(NSLocalizedString("settings.agents.webhook.url", comment: ""), text: $model.webhookUrl,
                              prompt: Text(verbatim: "https://your-server.com/webhook"))
                        .textFieldStyle(.roundedBorder)
                    Toggle(NSLocalizedString("settings.agents.webhook.enabled", comment: ""), isOn: $model.enabled)
                    Text(NSLocalizedString("settings.agents.webhook.agents", comment: ""))
                    ForEach(model.availableAgents, id: \.self) { agent in
                        Toggle(MacWebhookAgentLabel.label(for: agent), isOn: Binding(
                            get: { model.selectedAgents.contains(agent) },
                            set: { _ in model.toggleAgent(agent) }
                        ))
                    }
                    if model.selectedAgents.isEmpty {
                        Text(NSLocalizedString("settings.agents.webhook.no_agents", comment: ""))
                            .font(.caption).foregroundStyle(Theme.warning)
                    }
                    if model.settings.configured, model.settings.hasSecret == true {
                        Toggle(NSLocalizedString("settings.agents.webhook.regenerate", comment: ""), isOn: $model.regenerateSecret)
                    }
                    HStack {
                        Button(NSLocalizedString(
                            model.settings.configured ? "settings.agents.webhook.update" : "settings.agents.webhook.save",
                            comment: ""
                        )) { _Concurrency.Task { await model.save() } }
                        .disabled(!model.canSave)
                        if model.settings.configured {
                            Button(NSLocalizedString("settings.agents.webhook.remove", comment: ""), role: .destructive) { confirmRemove = true }
                                .disabled(model.isSaving)
                            Button(NSLocalizedString("settings.agents.webhook.test", comment: "")) { _Concurrency.Task { await model.test() } }
                                .disabled(model.isTesting || model.settings.enabled != true)
                        }
                        if model.isSaving || model.isTesting { ProgressView().controlSize(.small) }
                    }
                    Text(String(format: NSLocalizedString("settings.agents.webhook.url_hint", comment: ""), Brand.appName))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                if model.settings.configured {
                    Section(NSLocalizedString("settings.agents.webhook.status", comment: "")) {
                        let failures = model.settings.failureCount ?? 0
                        LabeledContent(NSLocalizedString("settings.agents.webhook.status", comment: ""),
                                       value: NSLocalizedString(model.settings.enabled == true ? "settings.agents.webhook.active" : "settings.agents.webhook.disabled", comment: ""))
                        LabeledContent(NSLocalizedString("settings.agents.webhook.no_failures", comment: ""),
                                       value: failures > 0 ? String(format: NSLocalizedString("settings.agents.webhook.failures", comment: ""), failures) : "✓")
                        if let lastFired = model.settings.lastFiredAt {
                            Text(String(format: NSLocalizedString("settings.agents.webhook.last_fired", comment: ""), lastFired))
                                .font(.caption).foregroundStyle(Theme.textMuted)
                        }
                        if let result = model.testResult {
                            Text(result.message ?? result.error ?? "")
                                .font(.caption).foregroundStyle(result.success ? Theme.success : Theme.error)
                        }
                    }
                }
            }
            .formStyle(.grouped).macThemedSurface()
        }
        .frame(width: 520, height: 560)
        .task { await model.load() }
        .confirmationDialog(NSLocalizedString("settings.agents.webhook.remove_confirm", comment: ""), isPresented: $confirmRemove) {
            Button(NSLocalizedString("settings.agents.webhook.remove", comment: ""), role: .destructive) {
                _Concurrency.Task { await model.delete() }
            }
        }
    }
}

enum MacWebhookAgentLabel {
    static func label(for agent: String) -> String {
        switch agent {
        case "claude": return "Claude"
        case "openai": return "OpenAI"
        case "gemini": return "Gemini"
        case "copilot": return "GitHub Copilot"
        default: return agent
        }
    }
}

// MARK: - Custom Agents sheet

struct MacCustomAgentsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CustomAgentsModel()
    @State private var newAgentName = ""
    @State private var agentToDelete: CustomAgent?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("settings.agents.custom.title", comment: "")).font(.headline)
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            Form {
                Section {
                    Text(NSLocalizedString("settings.openclaw.description", comment: ""))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                    if let message = model.errorMessage { Text(message).font(.caption).foregroundStyle(Theme.error) }
                    if let message = model.successMessage { Text(message).font(.caption).foregroundStyle(Theme.success) }
                }
                Section(NSLocalizedString("settings.openclaw.section", comment: "")) {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else if model.agents.isEmpty {
                        Text(NSLocalizedString("settings.openclaw.no_agents", comment: "")).foregroundStyle(Theme.textMuted)
                    }
                    ForEach(model.agents) { agent in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(agent.email).font(.system(.body, design: .monospaced))
                                Text(agent.status == "active"
                                     ? NSLocalizedString("settings.openclaw.status.active", comment: "")
                                     : NSLocalizedString("settings.openclaw.status.idle", comment: ""))
                                    .font(.caption).foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            if model.deletingId == agent.id || model.updatingPhotoId == agent.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Button(NSLocalizedString("mac.change_photo", comment: "")) { pickPhoto(for: agent) }
                                Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { agentToDelete = agent }
                            }
                        }
                    }
                }
                Section(NSLocalizedString("settings.openclaw.register_title", comment: "")) {
                    HStack {
                        TextField(NSLocalizedString("settings.openclaw.agent_name_placeholder", comment: ""), text: $newAgentName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: newAgentName) { newAgentName = newAgentName.lowercased() }
                        Button(NSLocalizedString("settings.openclaw.create_agent", comment: "")) {
                            _Concurrency.Task {
                                if await model.register(name: newAgentName) { newAgentName = "" }
                            }
                        }
                        .disabled(!CustomAgentNaming.isValid(newAgentName) || model.isRegistering)
                        if model.isRegistering { ProgressView().controlSize(.small) }
                    }
                    if !newAgentName.isEmpty && !CustomAgentNaming.isValid(newAgentName) {
                        Text(NSLocalizedString(
                            CustomAgentNaming.isReserved(newAgentName) ? "settings.openclaw.agent_name_reserved" : "settings.openclaw.agent_name_invalid",
                            comment: ""
                        )).font(.caption).foregroundStyle(Theme.error)
                    }
                    if let message = model.registerErrorMessage { Text(message).font(.caption).foregroundStyle(Theme.error) }
                    Text(NSLocalizedString("settings.openclaw.agent_name_hint", comment: ""))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                if let result = model.registrationResult {
                    Section(NSLocalizedString("settings.openclaw.credentials_title", comment: "")) {
                        Text(NSLocalizedString("settings.openclaw.credentials_warning", comment: ""))
                            .font(.caption).foregroundStyle(Theme.warning)
                        MacCopyableCode(code: MacCustomAgentCredentials.text(result))
                        Button(NSLocalizedString("actions.done", comment: "")) { model.registrationResult = nil }
                    }
                }
            }
            .formStyle(.grouped).macThemedSurface()
        }
        .frame(width: 520, height: 520)
        .task { await model.load() }
        .confirmationDialog(
            NSLocalizedString("settings.openclaw.delete_agent", comment: ""),
            isPresented: Binding(get: { agentToDelete != nil }, set: { if !$0 { agentToDelete = nil } }),
            presenting: agentToDelete
        ) { agent in
            Button(NSLocalizedString("settings.openclaw.delete_agent", comment: ""), role: .destructive) {
                _Concurrency.Task { await model.delete(agent) }
            }
        } message: { agent in
            Text(String(format: NSLocalizedString("settings.openclaw.delete_confirm", comment: ""), agent.email))
        }
    }

    private func pickPhoto(for agent: CustomAgent) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        _Concurrency.Task { await model.updatePhoto(agent, imageData: jpeg) }
    }
}

/// The one-time credentials as a single copyable block.
enum MacCustomAgentCredentials {
    static func text(_ result: CustomAgentRegistrationResult) -> String {
        """
        \(NSLocalizedString("settings.openclaw.credential.email", comment: "")): \(result.agent.email)
        \(NSLocalizedString("settings.openclaw.credential.client_id", comment: "")): \(result.oauth.clientId)
        \(NSLocalizedString("settings.openclaw.credential.client_secret", comment: "")): \(result.oauth.clientSecret)
        \(NSLocalizedString("settings.openclaw.credential.token_endpoint", comment: "")): \(result.config.tokenEndpoint)
        \(NSLocalizedString("settings.openclaw.credential.api_base", comment: "")): \(result.config.apiBase)
        \(NSLocalizedString("settings.openclaw.credential.sse_endpoint", comment: "")): \(result.config.sseEndpoint)
        """
    }
}

// MARK: - Copilot cloud agent (GitHub.com) sheet

struct MacCopilotCloudAgentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CopilotCloudAgentModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("settings.agents.copilot_cloud.title", comment: "")).font(.headline)
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            Form {
                Section {
                    Text(String(format: NSLocalizedString("settings.agents.copilot_cloud.description", comment: ""), Brand.appName))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                    Text(NSLocalizedString("settings.agents.copilot_cloud.oauth_warning", comment: ""))
                        .font(.caption).foregroundStyle(Theme.warning)
                }
                if let token = model.token {
                    Section(NSLocalizedString("settings.agents.copilot_cloud.token", comment: "")) {
                        Text(String(format: NSLocalizedString("settings.agents.copilot_cloud.secret_step", comment: ""), model.secretName)).font(.caption)
                        MacCopyableCode(code: token)
                    }
                    Section(NSLocalizedString("settings.agents.copilot_cloud.config", comment: "")) {
                        Text(NSLocalizedString("settings.agents.copilot_cloud.config_step", comment: "")).font(.caption)
                        MacCopyableCode(code: model.config)
                        Button(NSLocalizedString("settings.agents.copilot_cloud.open_docs", comment: "")) {
                            PlatformApplication.open(AgentHubLinks.githubCopilotMCPDocs)
                        }
                    }
                } else {
                    Section {
                        if let message = model.errorMessage { Text(message).font(.caption).foregroundStyle(Theme.error) }
                        if model.requiresWebSession { MacWebSessionRequiredRow() }
                        HStack {
                            Button(NSLocalizedString("settings.agents.copilot_cloud.create", comment: "")) {
                                _Concurrency.Task { await model.createToken() }
                            }.disabled(model.isCreating)
                            if model.isCreating { ProgressView().controlSize(.small) }
                        }
                    }
                }
            }
            .formStyle(.grouped).macThemedSurface()
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - Shared pieces

struct MacWebSessionRequiredRow: View {
    var body: some View {
        HStack {
            Text(NSLocalizedString("settings.agents.session_required", comment: ""))
                .font(.caption).foregroundStyle(Theme.warning)
            Spacer()
            if let url = AgentHubLinks.webAgentSettings(origin: Constants.API.baseURL) {
                Button(NSLocalizedString("settings.agents.open_web", comment: "")) { PlatformApplication.open(url) }
            }
        }
    }
}

struct MacCopyableCode: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(NSLocalizedString(copied ? "settings.agents.copied" : "actions.copy", comment: "")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
                _Concurrency.Task {
                    try? await _Concurrency.Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
            .controlSize(.small)
        }
        .padding(6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
#endif
