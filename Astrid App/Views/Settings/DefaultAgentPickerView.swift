import SwiftUI
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "DefaultAgentPicker")

/// View for selecting the default AI agent for chat
struct DefaultAgentPickerView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    @State private var agents: [AvailableAgent] = []
    @State private var currentSettings: AIAssistantSettings?
    @State private var selectedAgentId: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var keyStatuses: [String: Bool] = [:]  // service -> hasValidKey
    @State private var showAPIKeyManager = false
    @State private var apiKeyServiceToShow: AIService?

    /// Filter out the assistant itself — this selector picks the model that powers it.
    ///
    /// Matched on `service`, not on the email address: the assistant's address is
    /// brand-derived on the server (task 97208a72), so a hardcoded `astrid@astrid.cc`
    /// would list the assistant as a model option on any rebranded deployment.
    private var modelOptions: [AvailableAgent] {
        agents.filter { !$0.isDefaultAssistant }
    }

    /// Built-in models not yet returned by the API (no key configured)
    private var unconfiguredModels: [BuiltInModel] {
        let configuredServices = Set(modelOptions.map { $0.service })
        return BuiltInModel.allCases.filter { !configuredServices.contains($0.rawValue) }
    }

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
                    ProgressView()
                        .tint(Theme.accent)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let error = errorMessage {
                Section {
                    Text(error)
                        .font(Theme.Typography.body())
                        .foregroundColor(Theme.error)
                }
            } else {
                Section(footer: Text("Choose the model that powers \(Brand.appName) for My Tasks and your private lists. Mention @\(Brand.appName) in any chat or comment to get help.")) {
                    // Apple Intelligence (on-device, free) — shown first when available
                    if AppleFoundationModelService.shared.isAvailable {
                        Button {
                            selectAgent(kAppleFoundationModelId)
                        } label: {
                            HStack(spacing: Theme.spacing12) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .purple, .pink],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "apple.intelligence")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apple Intelligence")
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Text("Free \u{00B7} On-Device \u{00B7} Private")
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(.blue)
                                }

                                Spacer()

                                if selectedAgentId == kAppleFoundationModelId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                    }

                    // Cloud model options
                    ForEach(modelOptions) { agent in
                        Button {
                            selectAgent(agent.id)
                        } label: {
                            HStack(spacing: Theme.spacing12) {
                                agentAvatar(agent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Text(agent.serviceDisplayName)
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(.purple)
                                }

                                Spacer()

                                if selectedAgentId == agent.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                    }

                    // Unconfigured built-in models (no API key yet)
                    ForEach(unconfiguredModels, id: \.rawValue) { model in
                        Button {
                            apiKeyServiceToShow = AIService(rawValue: model.rawValue)
                            showAPIKeyManager = true
                        } label: {
                            HStack(spacing: Theme.spacing12) {
                                Image(model.imageAsset)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                    .opacity(0.5)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Text("\(model.subtitle) \u{00B7} API key required")
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(.orange)
                                }

                                Spacer()

                                Image(systemName: "key.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    // None option at the bottom
                    Button {
                        selectAgent(nil)
                    } label: {
                        HStack(spacing: Theme.spacing12) {
                            ZStack {
                                Circle()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "xmark")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("None")
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text("\(Brand.appName) won't auto-respond")
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }

                            Spacer()

                            if selectedAgentId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("\(Brand.appName)'s AI Model")
        .navigationBarTitleDisplayMode(.inline)
        .swipeToDismiss()
        .task { await loadData() }
        .navigationDestination(isPresented: $showAPIKeyManager) {
            AIAPIKeyManagerView()
        }
    }

    /// Resolve agent image URL: handles relative paths, prefers PNG over SVG for iOS
    private func resolvedAgentImageURL(_ agent: AvailableAgent) -> URL? {
        guard let image = agent.image, !image.isEmpty else { return nil }

        var path = image
        // iOS can't render SVG via AsyncImage — use PNG version instead
        if path.hasSuffix(".svg") {
            path = path.replacingOccurrences(of: ".svg", with: ".png")
        }
        // Resolve relative paths against API base URL
        if !path.hasPrefix("http") {
            let baseURL = Constants.API.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return URL(string: baseURL + path)
        }
        return URL(string: path)
    }

    @ViewBuilder
    private func agentAvatar(_ agent: AvailableAgent) -> some View {
        if let url = resolvedAgentImageURL(agent) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                default:
                    defaultAgentIcon(agent)
                }
            }
        } else {
            defaultAgentIcon(agent)
        }
    }

    @ViewBuilder
    private func defaultAgentIcon(_ agent: AvailableAgent) -> some View {
        if let asset = agent.serviceImageAsset {
            Image(asset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
            }
        }
    }

    private func selectAgent(_ agentId: String?) {
        selectedAgentId = agentId
        isSaving = true

        _Concurrency.Task {
            do {
                _ = try await ChatService.shared.updateAIAssistantSettings(
                    defaultAgentId: agentId
                )
                logger.notice("Updated default agent to: \(agentId ?? "none", privacy: .public)")
            } catch {
                logger.error("Failed to update default agent: \(error.localizedDescription, privacy: .public)")
                // Revert selection
                selectedAgentId = currentSettings?.defaultAgentId
            }
            isSaving = false
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let fetchedAgents = ChatService.shared.fetchAvailableAgents()
            async let fetchedSettings = ChatService.shared.getAIAssistantSettings()

            agents = try await fetchedAgents
            currentSettings = try await fetchedSettings
            selectedAgentId = currentSettings?.defaultAgentId

            // Auto-select Apple Intelligence for new users with no agent configured
            if selectedAgentId == nil && AppleFoundationModelService.shared.isAvailable {
                selectAgent(kAppleFoundationModelId)
            }

            // Cache agents for mention autocomplete
            AIAgentCache.shared.save(agents)
        } catch {
            errorMessage = "Failed to load agents"
            logger.error("Failed to load agent data: \(error.localizedDescription, privacy: .public)")
        }

        isLoading = false
    }
}

// MARK: - AIAgentCache Extension

extension AIAgentCache {
    func save(_ agents: [AvailableAgent]) {
        // Convert to User objects for the existing cache format
        let users = agents.map { agent in
            User(
                id: agent.id,
                email: agent.email,
                name: agent.name,
                image: agent.image,
                createdAt: nil,
                defaultDueTime: nil,
                isPending: nil,
                isAIAgent: true,
                aiAgentType: agent.service
            )
        }
        save(users)
    }

    func loadAsAgents() -> [AvailableAgent]? {
        guard let users = load() else { return nil }
        return users.map { user in
            AvailableAgent(
                id: user.id,
                name: user.displayName,
                email: user.email ?? "",
                image: user.image,
                service: user.aiAgentType ?? "unknown"
            )
        }
    }
}
