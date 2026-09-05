import SwiftUI

/**
 * Exploratory Features Settings View
 *
 * Provides access to alpha/experimental features:
 * - AI Assistants (API Key management)
 * - Apple Reminders sync
 */
struct AIAssistantSettingsView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Form {
            // Astrid's AI — top of the page
            Section(header: Text("\(Brand.appName)'s AI")) {
                NavigationLink(destination: DefaultAgentPickerView()) {
                    HStack {
                        Image("AstridCharacter")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Brand.appName)'s AI")
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text("Choose which AI model powers \(Brand.appName)")
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            // AI Assistants Section (API Keys + OpenClaw)
            Section(header: Text(NSLocalizedString("ai_assistants", comment: ""))) {
                NavigationLink(destination: AIAPIKeyManagerView()) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.ai.manage_keys", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("settings.ai.manage_keys_subtitle", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }

                NavigationLink(destination: OpenClawSettingsView()) {
                    HStack {
                        Image("ai-openclaw")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.openclaw.title", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("settings.openclaw.subtitle", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            // Apple Reminders Section
            Section(header: Text(NSLocalizedString("apple_reminders", comment: ""))) {
                NavigationLink(destination: AppleRemindersSettingsView()) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.reminders.configure_sync", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("settings.reminders.sync_subtitle", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            // Alpha Warning
            Section(footer: Text(NSLocalizedString("settings.exploratory.warning", comment: ""))) {
                EmptyView()
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("exploratory_features", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .swipeToDismiss()
    }
}

#Preview {
    NavigationStack {
        AIAssistantSettingsView()
    }
}

struct AIAgentRuntimeSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var modes: [String: AgentExecutionMode] = [:]
    @State private var keyStatuses: [String: AIAPIKeyStatus] = [:]
    @State private var copilotConnected = false
    @State private var expandedRowID: String?
    @State private var savingRowID: String?
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var actionErrorMessage: String?
    @State private var setupErrorMessage: String?
    @State private var copiedStep: String?
    @State private var keyInputs: [String: String] = [:]
    @State private var editingKeyServices: Set<String> = []
    @State private var keyOperationService: String?

    private let service = RemoteResourceService.shared

    var body: some View {
        Form {
            Section {
                Text(
                    String(
                        format: NSLocalizedString("settings.agents.description", comment: ""),
                        Brand.appName
                    )
                )
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text(NSLocalizedString("settings.agents.loading", comment: ""))
                    }
                }
            } else if let loadErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        Label(loadErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Button(NSLocalizedString("actions.retry", comment: "")) {
                            _Concurrency.Task { await load() }
                        }
                    }
                }
            } else {
                if let actionErrorMessage {
                    Section {
                        Label(actionErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.red)
                    }
                }

                if let setupErrorMessage {
                    Section {
                        Label(setupErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.orange)
                    }
                }

                ForEach(AgentRuntimeRow.all) { row in
                    agentSection(row)
                }

                Section(NSLocalizedString("settings.agents.preferences", comment: "")) {
                    NavigationLink(destination: DefaultAgentPickerView()) {
                        Label(
                            NSLocalizedString("settings.agents.default_model", comment: ""),
                            image: "AstridCharacter"
                        )
                    }

                    NavigationLink(destination: OpenClawSettingsView()) {
                        Label(NSLocalizedString("settings.openclaw.title", comment: ""), image: "ai-openclaw")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("settings.agents.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !isLoading else { return }
            _Concurrency.Task { await refreshCopilotStatus() }
        }
    }

    @ViewBuilder
    private func agentSection(_ row: AgentRuntimeRow) -> some View {
        let mode = mode(for: row)
        let isExpanded = expandedRowID == row.id

        Section {
            HStack(spacing: Theme.spacing12) {
                Button {
                    withAnimation {
                        expandedRowID = isExpanded ? nil : row.id
                    }
                } label: {
                    HStack(spacing: Theme.spacing12) {
                        agentIcon(row)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Theme.spacing8) {
                                Text(row.label)
                                    .foregroundStyle(.primary)
                                if !isConfigured(row, mode: mode) {
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
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if savingRowID == row.id {
                    ProgressView()
                        .controlSize(.small)
                }

                Menu {
                    ForEach(AgentExecutionMode.allCases) { candidate in
                        Button {
                            setMode(candidate, for: row)
                        } label: {
                            Label(candidate.localizedLabel, systemImage: candidate.systemImage)
                        }
                    }
                } label: {
                    Label(mode.localizedLabel, systemImage: mode.systemImage)
                        .font(Theme.Typography.caption1())
                        .lineLimit(1)
                }
                .disabled(savingRowID != nil)
            }

            if isExpanded {
                modeContent(mode, row: row)
            }
        }
        .opacity(mode == .off ? 0.65 : 1)
    }

    @ViewBuilder
    private func modeContent(_ mode: AgentExecutionMode, row: AgentRuntimeRow) -> some View {
        switch mode {
        case .api:
            VStack(alignment: .leading, spacing: Theme.spacing12) {
                Text(
                    String(
                        format: NSLocalizedString("settings.agents.api_description", comment: ""),
                        Brand.appName
                    )
                )
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)

                if row.usesOAuth {
                    Text(
                        NSLocalizedString(
                            copilotConnected
                                ? "settings.agents.copilot_connected"
                                : "settings.agents.copilot_disconnected",
                            comment: ""
                        )
                    )
                    .font(Theme.Typography.caption1())

                    Button {
                        if copilotConnected {
                            disconnectCopilot()
                        } else {
                            connectCopilot()
                        }
                    } label: {
                        Label(
                            NSLocalizedString(
                                copilotConnected
                                    ? "settings.agents.copilot_disconnect"
                                    : "settings.agents.copilot_connect",
                                comment: ""
                            ),
                            systemImage: "chevron.left.forwardslash.chevron.right"
                        )
                    }
                } else {
                    apiKeyEditor(row)
                }
            }

        case .polling:
            VStack(alignment: .leading, spacing: Theme.spacing12) {
                Text(
                    String(
                        format: NSLocalizedString("settings.agents.polling_description", comment: ""),
                        row.label
                    )
                )
                .font(Theme.Typography.caption1())
                .foregroundStyle(.secondary)

                ForEach(
                    AgentHarnessRecipes.recipes(
                        for: row.pollMailbox,
                        origin: Constants.API.baseURL,
                        serverName: Brand.wordmark.lowercased()
                    )
                ) { recipe in
                    DisclosureGroup(recipe.name) {
                        VStack(alignment: .leading, spacing: Theme.spacing12) {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                codeBlock(step, id: "\(recipe.id)-\(index)")
                            }
                        }
                        .padding(.top, Theme.spacing8)
                    }
                }
            }

        case .webhook:
            VStack(alignment: .leading, spacing: Theme.spacing12) {
                Text(NSLocalizedString("settings.agents.webhook_description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundStyle(.secondary)

                Button {
                    let base = Constants.API.baseURL.trimmingCharacters(
                        in: CharacterSet(charactersIn: "/")
                    )
                    if let url = URL(string: "\(base)/settings/agents") {
                        openURL(url)
                    }
                } label: {
                    Label(
                        NSLocalizedString("settings.agents.webhook_configure", comment: ""),
                        systemImage: "safari"
                    )
                }
            }

        case .off:
            Text(
                String(
                    format: NSLocalizedString("settings.agents.off_description", comment: ""),
                    Brand.appName
                )
            )
            .font(Theme.Typography.caption1())
            .foregroundStyle(.secondary)
        }
    }

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
    private func apiKeyEditor(_ row: AgentRuntimeRow) -> some View {
        let status = keyStatuses[row.service]
        let isEditing = status?.hasKey != true || editingKeyServices.contains(row.service)
        let isBusy = keyOperationService == row.service

        if isEditing {
            SecureField(
                AIService(rawValue: row.service)?.keyPlaceholder
                    ?? NSLocalizedString("settings.agents.manage_key", comment: ""),
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
                    saveKey(for: row.service)
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
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                }

                Spacer()

                if isBusy {
                    ProgressView()
                } else {
                    Button(NSLocalizedString("settings.agents.test_key", comment: "")) {
                        testKey(for: row.service)
                    }
                    Button(NSLocalizedString("actions.update", comment: "")) {
                        editingKeyServices.insert(row.service)
                    }
                    Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                        deleteKey(for: row.service)
                    }
                }
            }
            .font(Theme.Typography.caption1())
        }
    }

    private func codeBlock(_ code: String, id: String) -> some View {
        VStack(alignment: .trailing, spacing: Theme.spacing8) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                UIPasteboard.general.string = code
                copiedStep = id
                _Concurrency.Task {
                    try? await _Concurrency.Task.sleep(for: .seconds(2))
                    if copiedStep == id {
                        copiedStep = nil
                    }
                }
            } label: {
                Label(
                    NSLocalizedString(
                        copiedStep == id ? "settings.agents.copied" : "actions.copy",
                        comment: ""
                    ),
                    systemImage: copiedStep == id ? "checkmark" : "doc.on.doc"
                )
            }
            .font(Theme.Typography.caption2())
        }
        .padding(Theme.spacing8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func mode(for row: AgentRuntimeRow) -> AgentExecutionMode {
        modes[row.modeMailbox] ?? .polling
    }

    private func isConfigured(_ row: AgentRuntimeRow, mode: AgentExecutionMode) -> Bool {
        guard mode == .api else { return true }
        if row.usesOAuth { return copilotConnected }
        return keyStatuses[row.service]?.hasKey == true
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadErrorMessage = nil
        actionErrorMessage = nil
        setupErrorMessage = nil
        defer { isLoading = false }

        do {
            modes = try await service.getAgentModes().modes
        } catch {
            loadErrorMessage = String(
                format: NSLocalizedString("settings.agents.load_failed", comment: ""),
                error.localizedDescription
            )
            return
        }

        do {
            keyStatuses = try await service.getAIAPIKeys().keys
        } catch {
            setupErrorMessage = error.localizedDescription
        }

        await refreshCopilotStatus()
    }

    @MainActor
    private func refreshCopilotStatus() async {
        do {
            copilotConnected = try await service.getCopilotIntegrationStatus().connected
        } catch {
            setupErrorMessage = error.localizedDescription
        }
    }

    private func setMode(_ mode: AgentExecutionMode, for row: AgentRuntimeRow) {
        let previous = modes[row.modeMailbox]
        modes[row.modeMailbox] = mode
        expandedRowID = row.id
        savingRowID = row.id
        actionErrorMessage = nil

        _Concurrency.Task {
            do {
                let response = try await service.updateAgentMode(
                    agent: row.modeMailbox,
                    mode: mode
                )
                modes = response.modes
            } catch {
                if let previous {
                    modes[row.modeMailbox] = previous
                } else {
                    modes.removeValue(forKey: row.modeMailbox)
                }
                actionErrorMessage = String(
                    format: NSLocalizedString("settings.agents.save_failed", comment: ""),
                    error.localizedDescription
                )
            }
            savingRowID = nil
        }
    }

    private func connectCopilot() {
        _Concurrency.Task {
            do {
                let response = try await service.getCopilotAuthorization()
                guard let url = URL(string: response.url) else {
                    throw URLError(.badURL)
                }
                openURL(url)
            } catch {
                setupErrorMessage = error.localizedDescription
            }
        }
    }

    private func disconnectCopilot() {
        _Concurrency.Task {
            do {
                copilotConnected = try await service.disconnectCopilot().connected
            } catch {
                setupErrorMessage = error.localizedDescription
            }
        }
    }

    private func saveKey(for serviceID: String) {
        guard let key = keyInputs[serviceID], !key.isEmpty else { return }
        keyOperationService = serviceID
        actionErrorMessage = nil

        _Concurrency.Task {
            do {
                _ = try await service.saveAIAPIKey(serviceId: serviceID, apiKey: key)
                keyStatuses = try await service.getAIAPIKeys().keys
                keyInputs[serviceID] = ""
                editingKeyServices.remove(serviceID)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
            keyOperationService = nil
        }
    }

    private func testKey(for serviceID: String) {
        keyOperationService = serviceID
        actionErrorMessage = nil

        _Concurrency.Task {
            do {
                let result = try await service.testAIAPIKey(serviceId: serviceID)
                let current = keyStatuses[serviceID]
                keyStatuses[serviceID] = AIAPIKeyStatus(
                    hasKey: current?.hasKey ?? true,
                    keyPreview: current?.keyPreview,
                    isValid: result.success,
                    lastTested: current?.lastTested,
                    error: result.error
                )
                if let error = result.error {
                    actionErrorMessage = error
                }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
            keyOperationService = nil
        }
    }

    private func deleteKey(for serviceID: String) {
        keyOperationService = serviceID
        actionErrorMessage = nil

        _Concurrency.Task {
            do {
                _ = try await service.deleteAIAPIKey(serviceId: serviceID)
                keyStatuses.removeValue(forKey: serviceID)
                editingKeyServices.insert(serviceID)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
            keyOperationService = nil
        }
    }
}
