import SwiftUI

/// Available AI service providers
enum AIService: String, CaseIterable, Identifiable {
    case claude = "claude"
    case openai = "openai"
    case gemini = "gemini"
    case copilot = "copilot"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .copilot: return "GitHub Copilot"
        }
    }

    var description: String {
        switch self {
        case .claude: return "Claude AI for task assistance and coding"
        case .openai: return "GPT-4 for task assistance and coding"
        case .gemini: return "Gemini for task assistance and coding"
        case .copilot: return "GitHub Copilot (OpenAI-compatible; requires an active Copilot subscription token)"
        }
    }

    var imageAsset: String {
        switch self {
        case .claude: return "ai-claude"
        case .openai: return "ai-openai"
        case .gemini: return "ai-gemini"
        case .copilot: return "ai-copilot"   // no bundled asset → falls back to fallbackSystemIcon
        }
    }

    /// SF Symbol used when `imageAsset` is not a bundled image (keeps the row from showing blank).
    var fallbackSystemIcon: String {
        switch self {
        case .copilot: return "chevron.left.forwardslash.chevron.right"
        default: return "cpu"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        case .copilot: return "Copilot token"
        }
    }

    var documentationURL: URL? {
        switch self {
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .copilot: return URL(string: "https://docs.github.com/en/copilot")
        }
    }
}

/// Status for a single API key
struct APIKeyUIStatus {
    var hasKey: Bool = false
    var keyPreview: String?
    var isValid: Bool?
    var lastTested: String?
    var error: String?
    var isLoading: Bool = false
    var isTesting: Bool = false
    var isSaving: Bool = false
    var isDeleting: Bool = false
}

/// View for managing AI API keys
struct AIAPIKeyManagerView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL

    @State private var keyStatuses: [AIService: APIKeyUIStatus] = [:]
    @State private var expandedService: AIService?
    @State private var apiKeyInput: String = ""
    @State private var showKeyInput: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isLoading = true

    private let apiClient = RemoteResourceService.shared

    var body: some View {
        Form {
            // Header
            Section {
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(Theme.accent)
                        Text(NSLocalizedString("setting.ai.api_keys", comment: ""))
                            .font(Theme.Typography.headline())
                    }

                    Text(NSLocalizedString("settings.ai.api_keys_description", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }

            // Success/Error messages
            if let successMessage = successMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(successMessage)
                            .font(Theme.Typography.body())
                            .foregroundColor(.green)
                    }
                }
            }

            if let errorMessage = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(Theme.Typography.body())
                            .foregroundColor(.red)
                    }
                }
            }

            // Service list
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("settings.ai.loading_keys", comment: ""))
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                }
            } else {
                ForEach(AIService.allCases) { service in
                    serviceSection(for: service)
                }
            }

            // Info section
            Section {
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text(NSLocalizedString("settings.ai.about_keys", comment: ""))
                        .font(Theme.Typography.subheadline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    Text(NSLocalizedString("settings.ai.about_description", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    Text(NSLocalizedString("settings.ai.encryption_info", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("setting.ai.api_keys", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAPIKeys()
        }
    }

    @ViewBuilder
    private func serviceSection(for service: AIService) -> some View {
        let status = keyStatuses[service] ?? APIKeyUIStatus()
        let isExpanded = expandedService == service

        Section {
            // Service header row
            Button(action: {
                withAnimation {
                    if expandedService == service {
                        expandedService = nil
                    } else {
                        expandedService = service
                        apiKeyInput = ""
                        showKeyInput = false
                    }
                }
            }) {
                HStack(spacing: Theme.spacing12) {
                    // Service icon (bundled asset, or SF Symbol fallback for services without one)
                    Group {
                        if UIImage(named: service.imageAsset) != nil {
                            Image(service.imageAsset).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: service.fallbackSystemIcon).resizable().aspectRatio(contentMode: .fit)
                                .padding(7).foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    // Service info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.displayName)
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                        if status.hasKey {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor(for: status))
                                    .frame(width: 6, height: 6)
                                Text(statusText(for: status))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                                if let preview = status.keyPreview {
                                    Text("(\(preview))")
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        } else {
                            Text(NSLocalizedString("settings.ai.not_configured", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spacing12) {
                    Text(service.description)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    // API Key input
                    if status.hasKey && !showKeyInput {
                        // Show existing key actions
                        HStack(spacing: Theme.spacing12) {
                            Button(action: {
                                testKey(for: service)
                            }) {
                                HStack {
                                    if status.isTesting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "checkmark.circle")
                                    }
                                    Text("Test Key")
                                }
                                .font(Theme.Typography.caption1())
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .disabled(status.isTesting)
                            .buttonStyle(.plain)

                            Button(action: {
                                showKeyInput = true
                            }) {
                                HStack {
                                    Image(systemName: "pencil")
                                    Text("Update")
                                }
                                .font(Theme.Typography.caption1())
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                deleteKey(for: service)
                            }) {
                                HStack {
                                    if status.isDeleting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "trash")
                                    }
                                    Text("Delete")
                                }
                                .font(Theme.Typography.caption1())
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .disabled(status.isDeleting)
                            .buttonStyle(.plain)
                        }

                        if let error = status.error {
                            Text(error)
                                .font(Theme.Typography.caption2())
                                .foregroundColor(.red)
                        }
                    } else {
                        // Show key input field
                        VStack(alignment: .leading, spacing: Theme.spacing8) {
                            SecureField(service.keyPlaceholder, text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.Typography.body())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)

                            HStack(spacing: Theme.spacing12) {
                                Button(action: {
                                    saveKey(for: service)
                                }) {
                                    HStack {
                                        if status.isSaving {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "checkmark")
                                        }
                                        Text("Save")
                                    }
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(apiKeyInput.isEmpty ? Color.gray : Theme.accent)
                                    .cornerRadius(8)
                                }
                                .disabled(apiKeyInput.isEmpty || status.isSaving)
                                .buttonStyle(.plain)

                                if status.hasKey {
                                    Button(action: {
                                        showKeyInput = false
                                        apiKeyInput = ""
                                    }) {
                                        Text("Cancel")
                                            .font(Theme.Typography.caption1())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Spacer()

                                if let url = service.documentationURL {
                                    Button(action: {
                                        openURL(url)
                                    }) {
                                        HStack {
                                            Image(systemName: "arrow.up.right.square")
                                            Text(NSLocalizedString("debug.get_key", comment: "Get Key"))
                                        }
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.top, Theme.spacing8)
            }
        }
    }

    private func statusColor(for status: APIKeyUIStatus) -> Color {
        if status.isValid == true {
            return .green
        } else if status.isValid == false {
            return .red
        } else {
            return .orange
        }
    }

    private func statusText(for status: APIKeyUIStatus) -> String {
        if status.isTesting {
            return "Testing..."
        } else if status.isValid == true {
            return "Valid"
        } else if status.isValid == false {
            return "Invalid"
        } else {
            return "Configured"
        }
    }

    // MARK: - API Operations

    private func loadAPIKeys() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.getAIAPIKeys()

            var newStatuses: [AIService: APIKeyUIStatus] = [:]
            for service in AIService.allCases {
                if let keyStatus = response.keys[service.rawValue] {
                    newStatuses[service] = APIKeyUIStatus(
                        hasKey: keyStatus.hasKey,
                        keyPreview: keyStatus.keyPreview,
                        isValid: keyStatus.isValid,
                        lastTested: keyStatus.lastTested,
                        error: keyStatus.error
                    )
                } else {
                    newStatuses[service] = APIKeyUIStatus()
                }
            }

            keyStatuses = newStatuses
        } catch {
            print("Failed to load API keys: \(error)")
            errorMessage = "Failed to load API keys"

            // Initialize empty statuses
            for service in AIService.allCases {
                keyStatuses[service] = APIKeyUIStatus()
            }
        }
    }

    private func saveKey(for service: AIService) {
        guard !apiKeyInput.isEmpty else { return }

        var status = keyStatuses[service] ?? APIKeyUIStatus()
        status.isSaving = true
        keyStatuses[service] = status

        _Concurrency.Task {
            defer {
                var status = keyStatuses[service] ?? APIKeyUIStatus()
                status.isSaving = false
                keyStatuses[service] = status
            }

            do {
                _ = try await apiClient.saveAIAPIKey(serviceId: service.rawValue, apiKey: apiKeyInput)

                // Update status
                var status = keyStatuses[service] ?? APIKeyUIStatus()
                status.hasKey = true
                status.isValid = nil // Will be set when tested
                status.error = nil
                keyStatuses[service] = status

                // Clear input and collapse
                apiKeyInput = ""
                showKeyInput = false

                successMessage = "\(service.displayName) key saved successfully"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    successMessage = nil
                }

                // Reload to get preview
                await loadAPIKeys()
            } catch {
                print("Failed to save API key: \(error)")
                errorMessage = "Failed to save key: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    errorMessage = nil
                }
            }
        }
    }

    private func testKey(for service: AIService) {
        var status = keyStatuses[service] ?? APIKeyUIStatus()
        status.isTesting = true
        status.error = nil
        keyStatuses[service] = status

        _Concurrency.Task {
            defer {
                var status = keyStatuses[service] ?? APIKeyUIStatus()
                status.isTesting = false
                keyStatuses[service] = status
            }

            do {
                let response = try await apiClient.testAIAPIKey(serviceId: service.rawValue)

                var status = keyStatuses[service] ?? APIKeyUIStatus()
                status.isValid = response.success
                status.error = response.error
                keyStatuses[service] = status

                if response.success {
                    successMessage = "\(service.displayName) key is valid!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        successMessage = nil
                    }
                }
            } catch {
                print("Failed to test API key: \(error)")
                var status = keyStatuses[service] ?? APIKeyUIStatus()
                status.isValid = false
                status.error = error.localizedDescription
                keyStatuses[service] = status
            }
        }
    }

    private func deleteKey(for service: AIService) {
        var status = keyStatuses[service] ?? APIKeyUIStatus()
        status.isDeleting = true
        keyStatuses[service] = status

        _Concurrency.Task {
            defer {
                var status = keyStatuses[service] ?? APIKeyUIStatus()
                status.isDeleting = false
                keyStatuses[service] = status
            }

            do {
                _ = try await apiClient.deleteAIAPIKey(serviceId: service.rawValue)

                // Reset status
                keyStatuses[service] = APIKeyUIStatus()

                successMessage = "\(service.displayName) key deleted"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    successMessage = nil
                }
            } catch {
                print("Failed to delete API key: \(error)")
                errorMessage = "Failed to delete key: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    errorMessage = nil
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AIAPIKeyManagerView()
    }
}
