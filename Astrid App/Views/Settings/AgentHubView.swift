//  AgentHubView.swift
//  The iOS Agent Hub (AITD-297) — native equivalent of astrid-web's Agent Hub.
//
//  Per provider row the first question is who owns the runtime; the transport appears only
//  under "I run it". State and every rule live in `AgentHubModel` (shared with Mac); this file
//  is layout plus the two iOS-only mechanics: the in-app OAuth sheet and the pasteboard.

import SwiftUI

struct AgentHubView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AgentHubModel()
    @StateObject private var capabilities = ServerCapabilityService.shared

    @State private var keyInputs: [String: String] = [:]
    @State private var editingKeyServices: Set<String> = []
    @State private var showCustomAgents = false

    private var origin: String { Constants.API.baseURL }

    var body: some View {
        Form {
            introSection

            if model.isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text(NSLocalizedString("settings.agents.loading", comment: ""))
                    }
                }
            } else if let loadErrorMessage = model.loadErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        Label(loadErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Button(NSLocalizedString("actions.retry", comment: "")) {
                            _Concurrency.Task { await model.load() }
                        }
                    }
                }
            } else {
                if let actionErrorMessage = model.actionErrorMessage {
                    Section {
                        Label(actionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.red)
                    }
                }
                if let setupErrorMessage = model.setupErrorMessage {
                    Section {
                        Label(setupErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.orange)
                    }
                }

                ForEach(model.rows) { row in
                    agentSection(row)
                }

                if capabilities.capabilities.integrations.customAgents {
                    customAgentsSection
                }

                assistantModelSection
                githubSection
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("settings.agents.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showCustomAgents) { CustomAgentsSettingsView() }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !model.isLoading else { return }
            _Concurrency.Task { await model.refreshCopilotStatus() }
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            Text(String(format: NSLocalizedString("settings.agents.description", comment: ""), Brand.appName))
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)
            if capabilities.capabilities.integrations.mcp, let guide = AgentHubLinks.loopsGuide(origin: origin) {
                Button {
                    openURL(guide)
                } label: {
                    Label(NSLocalizedString("settings.agents.guide_link", comment: ""), systemImage: "book")
                }
                if let download = AgentHubLinks.workflowDownload(origin: origin) {
                    Button {
                        openURL(download)
                    } label: {
                        Label(NSLocalizedString("settings.agents.download_skill", comment: ""), systemImage: "arrow.down.doc")
                    }
                }
            }
        } header: {
            Text(NSLocalizedString("settings.agents.your_agents", comment: ""))
        }
    }

    @ViewBuilder
    private func agentSection(_ row: AgentRuntimeRow) -> some View {
        let mode = model.mode(for: row)
        let ownership = mode.ownership

        Section {
            HStack(spacing: Theme.spacing12) {
                agentIcon(row)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.spacing8) {
                        Text(row.label)
                        if !model.isConfigured(row) && mode != .off {
                            Text(NSLocalizedString("settings.agents.needs_setup", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("\(row.identityMailbox(for: mode))@\(Brand.agentEmailDomain)")
                        .font(Theme.Typography.caption2())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.savingRowID == row.id {
                    ProgressView().controlSize(.small)
                }
            }

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
            .disabled(model.savingRowID != nil)

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
                        Label(transport.localizedLabel, systemImage: transport.systemImage).tag(transport)
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
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)
            if row.usesOAuth {
                copilotConnection
            } else {
                apiKeyEditor(row)
            }

        case .polling:
            Text(String(format: NSLocalizedString("settings.agents.polling_description", comment: ""), row.label))
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("settings.agents.polling_guide_hint", comment: ""))
                .font(Theme.Typography.caption2())
                .foregroundStyle(.secondary)
            if row.usesOAuth && capabilities.capabilities.integrations.mcp {
                // The Copilot app / GitHub.com cloud agent is one of Copilot's harnesses, so its
                // token + repository MCP setup lives inside this row, not at page level.
                NavigationLink(destination: CopilotCloudAgentSetupView()) {
                    Label(NSLocalizedString("settings.agents.copilot_cloud.title", comment: ""),
                          systemImage: "cloud.fill")
                }
            }

        case .webhook:
            Text(NSLocalizedString("settings.agents.webhook_description", comment: ""))
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)
            NavigationLink(destination: WebhookSettingsView()) {
                Label(NSLocalizedString("settings.agents.webhook.configure", comment: ""),
                      systemImage: "point.3.connected.trianglepath.dotted")
            }

        case .off:
            Text(String(format: NSLocalizedString("settings.agents.off_description", comment: ""), Brand.appName))
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)
        }
    }

    private var customAgentsSection: some View {
        Section {
            NavigationLink(destination: CustomAgentsSettingsView()) {
                HStack(spacing: Theme.spacing12) {
                    Image("ai-openclaw")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("settings.agents.custom.title", comment: ""))
                        Text(NSLocalizedString("settings.agents.custom.subtitle", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var assistantModelSection: some View {
        Section {
            NavigationLink(destination: DefaultAgentPickerView()) {
                Label(
                    String(format: NSLocalizedString("settings.agents.model.title", comment: ""), Brand.appName),
                    image: "AstridCharacter"
                )
            }
        } footer: {
            Text(String(format: NSLocalizedString("settings.agents.model.description", comment: ""), Brand.appName))
        }
    }

    private var githubSection: some View {
        GitHubConnectionSection()
    }

    // MARK: - Pieces

    @ViewBuilder
    private func agentIcon(_ row: AgentRuntimeRow) -> some View {
        if let asset = row.imageAsset, UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
        } else {
            Image(systemName: row.fallbackSystemImage)
                .frame(width: 30, height: 30)
                .foregroundStyle(Theme.accent)
        }
    }

    @ViewBuilder
    private var copilotConnection: some View {
        Text(NSLocalizedString(
            model.copilotConnected ? "settings.agents.copilot_connected" : "settings.agents.copilot_disconnected",
            comment: ""
        ))
        .font(Theme.Typography.caption1())

        if model.isPollingCopilot {
            HStack {
                ProgressView().controlSize(.small)
                Text(NSLocalizedString("settings.agents.copilot_waiting", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                if model.copilotConnected {
                    _Concurrency.Task { await model.disconnectCopilot() }
                } else {
                    connectCopilot()
                }
            } label: {
                Label(
                    NSLocalizedString(
                        model.copilotConnected ? "settings.agents.copilot_disconnect" : "settings.agents.copilot_connect",
                        comment: ""
                    ),
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
            }
        }
    }

    /// GitHub OAuth in an in-app session. The server-side callback ends on a "return to the app"
    /// page rather than an app-scheme redirect, so the session closes by hand and the status is
    /// polled afterwards.
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
    private func apiKeyEditor(_ row: AgentRuntimeRow) -> some View {
        let status = model.keyStatuses[row.service]
        let isEditing = status?.hasKey != true || editingKeyServices.contains(row.service)
        let isBusy = model.keyOperationService == row.service

        if isEditing {
            SecureField(
                status?.hasKey == true
                    ? NSLocalizedString("settings.agents.key_replace_placeholder", comment: "")
                    : (AIService(rawValue: row.service)?.keyPlaceholder ?? NSLocalizedString("settings.agents.manage_key", comment: "")),
                text: Binding(
                    get: { keyInputs[row.service] ?? "" },
                    set: { keyInputs[row.service] = $0 }
                )
            )
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            HStack {
                Button {
                    let key = keyInputs[row.service] ?? ""
                    _Concurrency.Task {
                        await model.saveKey(key, for: row.service)
                        if model.actionErrorMessage == nil {
                            keyInputs[row.service] = ""
                            editingKeyServices.remove(row.service)
                        }
                    }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Label(NSLocalizedString("actions.save", comment: ""), systemImage: "checkmark")
                    }
                }
                .disabled((keyInputs[row.service] ?? "").isEmpty || isBusy)

                if status?.hasKey == true {
                    Button(NSLocalizedString("actions.cancel", comment: "")) {
                        editingKeyServices.remove(row.service)
                        keyInputs[row.service] = ""
                    }
                    .disabled(isBusy)
                }
            }
        } else {
            HStack {
                Image(systemName: status?.isValid == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status?.isValid == false ? .red : .green)
                if let preview = status?.keyPreview {
                    Text(preview).font(.system(.caption, design: .monospaced))
                }
                Spacer()
                if isBusy {
                    ProgressView()
                } else {
                    Button(NSLocalizedString("settings.agents.test_key", comment: "")) {
                        _Concurrency.Task { await model.testKey(for: row.service) }
                    }
                    Button(NSLocalizedString("actions.update", comment: "")) {
                        editingKeyServices.insert(row.service)
                    }
                    Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                        _Concurrency.Task {
                            await model.deleteKey(for: row.service)
                            editingKeyServices.insert(row.service)
                        }
                    }
                }
            }
            .font(Theme.Typography.caption1())
            .buttonStyle(.borderless)
        }

        HStack(spacing: Theme.spacing4) {
            Text(NSLocalizedString("settings.agents.key_footer", comment: ""))
            if let docs = AIService(rawValue: row.service)?.documentationURL {
                Button(NSLocalizedString("settings.agents.get_key", comment: "")) { openURL(docs) }
                    .buttonStyle(.borderless)
            }
        }
        .font(Theme.Typography.caption2())
        .foregroundStyle(.secondary)
    }
}

// MARK: - GitHub App connection (account-level, server-run only)

/// Only "Astrid runs it" needs this: server-run agents create branches and PRs through the
/// GitHub App. The install/manage flow is web-only (`/api/github/*`), so this shows status and
/// deep-links out rather than reimplementing it.
struct GitHubConnectionSection: View {
    @Environment(\.openURL) private var openURL
    @State private var status: GitHubStatusResponse?
    @State private var failed = false

    var body: some View {
        Section {
            HStack {
                Image(systemName: status?.isGitHubConnected == true ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(status?.isGitHubConnected == true ? .green : .secondary)
                if let status {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString(
                            status.isGitHubConnected ? "settings.agents.github.connected" : "settings.agents.github.not_connected",
                            comment: ""
                        ))
                        if status.isGitHubConnected {
                            Text(String(format: NSLocalizedString("settings.agents.github.repositories", comment: ""), status.repositoryCount))
                                .font(Theme.Typography.caption2())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if failed {
                    Text(NSLocalizedString("settings.agents.github.not_connected", comment: ""))
                } else {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let url = AgentHubLinks.webAgentSettings(origin: Constants.API.baseURL) {
                    Button(NSLocalizedString("settings.agents.github.manage", comment: "")) { openURL(url) }
                        .font(Theme.Typography.caption1())
                }
            }
        } header: {
            Label(NSLocalizedString("settings.agents.github.title", comment: ""), systemImage: "chevron.left.forwardslash.chevron.right")
        } footer: {
            Text(String(format: NSLocalizedString("settings.agents.github.description", comment: ""), Brand.appName))
        }
        .task {
            do {
                status = try await RemoteResourceService.shared.getGitHubStatus()
            } catch {
                failed = true
            }
        }
    }
}

// MARK: - Copilot cloud agent (GitHub.com) setup

struct CopilotCloudAgentSetupView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var model = CopilotCloudAgentModel()
    @State private var copiedField: String?

    var body: some View {
        Form {
            Section {
                Text(String(format: NSLocalizedString("settings.agents.copilot_cloud.description", comment: ""), Brand.appName))
                    .font(Theme.Typography.caption1())
                    .foregroundStyle(.secondary)
                Label(NSLocalizedString("settings.agents.copilot_cloud.oauth_warning", comment: ""), systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.caption1())
                    .foregroundStyle(.orange)
            }

            if let token = model.token {
                Section(NSLocalizedString("settings.agents.copilot_cloud.token", comment: "")) {
                    Text(String(format: NSLocalizedString("settings.agents.copilot_cloud.secret_step", comment: ""), model.secretName))
                        .font(Theme.Typography.caption1())
                    CopyableCodeBlock(code: token, id: "token", copiedField: $copiedField)
                }
                Section(NSLocalizedString("settings.agents.copilot_cloud.config", comment: "")) {
                    Text(NSLocalizedString("settings.agents.copilot_cloud.config_step", comment: ""))
                        .font(Theme.Typography.caption1())
                    CopyableCodeBlock(code: model.config, id: "config", copiedField: $copiedField)
                    Button {
                        openURL(AgentHubLinks.githubCopilotMCPDocs)
                    } label: {
                        Label(NSLocalizedString("settings.agents.copilot_cloud.open_docs", comment: ""), systemImage: "safari")
                    }
                }
            } else {
                Section {
                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.red)
                    }
                    if model.requiresWebSession {
                        WebSessionRequiredRow()
                    }
                    Button {
                        _Concurrency.Task { await model.createToken() }
                    } label: {
                        HStack {
                            Label(NSLocalizedString("settings.agents.copilot_cloud.create", comment: ""), systemImage: "key.fill")
                            if model.isCreating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isCreating)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("settings.agents.copilot_cloud.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Do this on the web" — for the writes the server only accepts from an interactive session.
struct WebSessionRequiredRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            Text(NSLocalizedString("settings.agents.session_required", comment: ""))
                .font(Theme.Typography.caption1())
                .foregroundStyle(.orange)
            if let url = AgentHubLinks.webAgentSettings(origin: Constants.API.baseURL) {
                Button {
                    openURL(url)
                } label: {
                    Label(NSLocalizedString("settings.agents.open_web", comment: ""), systemImage: "safari")
                }
            }
        }
    }
}

/// Monospaced, selectable code with a copy button and a two-second "Copied" acknowledgement.
struct CopyableCodeBlock: View {
    let code: String
    let id: String
    @Binding var copiedField: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.spacing8) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                UIPasteboard.general.string = code
                copiedField = id
                _Concurrency.Task {
                    try? await _Concurrency.Task.sleep(for: .seconds(2))
                    if copiedField == id { copiedField = nil }
                }
            } label: {
                Label(
                    NSLocalizedString(copiedField == id ? "settings.agents.copied" : "actions.copy", comment: ""),
                    systemImage: copiedField == id ? "checkmark" : "doc.on.doc"
                )
            }
            .font(Theme.Typography.caption2())
            .buttonStyle(.borderless)
        }
        .padding(Theme.spacing8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        AgentHubView()
    }
}
