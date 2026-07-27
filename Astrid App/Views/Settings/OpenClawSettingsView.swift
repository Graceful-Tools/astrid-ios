import SwiftUI

/// View for managing OpenClaw agents (AI agent registration and credentials)
struct OpenClawSettingsView: View {
    @Environment(\.colorScheme) var colorScheme

    @State private var agents: [OpenClawAgent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Registration sheet state
    @State private var showRegisterSheet = false
    @State private var newAgentName = ""
    @State private var isRegistering = false
    @State private var registerError: String?

    // Credentials sheet (shown once after registration)
    @State private var registrationResult: OpenClawRegistrationResult?

    // Delete state
    @State private var deletingId: String?
    @State private var agentToDelete: OpenClawAgent?

    // Copy feedback
    @State private var copiedField: String?

    private let apiClient = RemoteResourceService.shared

    private static let reservedNames: Set<String> = [
        "admin", "system", "test", "api", "support", "root", "openclaw"
    ]

    private static let namePattern = try! NSRegularExpression(
        pattern: "^[a-z0-9][a-z0-9._-]{0,30}[a-z0-9]$"
    )

    var body: some View {
        Form {
            // Header
            headerSection

            // Messages
            if let successMessage = successMessage {
                successMessageSection(successMessage)
            }

            if let errorMessage = errorMessage {
                errorMessageSection(errorMessage)
            }

            // Agent list
            if isLoading {
                loadingSection
            } else if agents.isEmpty {
                emptyStateSection
            } else {
                agentsSection
            }

            // Connect agent button
            connectAgentSection

            // Info section
            infoSection

            // Tip section
            tipSection
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("settings.openclaw.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .swipeToDismiss()
        .sheet(isPresented: $showRegisterSheet) {
            registerAgentSheet
        }
        .sheet(item: $registrationResult) { result in
            credentialsSheet(result)
        }
        .confirmationDialog(
            NSLocalizedString("settings.openclaw.delete_agent", comment: ""),
            isPresented: .init(
                get: { agentToDelete != nil },
                set: { if !$0 { agentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let agent = agentToDelete {
                Button(NSLocalizedString("settings.openclaw.delete_agent", comment: ""), role: .destructive) {
                    _Concurrency.Task { await deleteAgent(agentId: agent.id) }
                }
            }
        } message: {
            if let agent = agentToDelete {
                Text(String(format: NSLocalizedString("settings.openclaw.delete_confirm", comment: ""), agent.email))
            }
        }
        .task {
            await loadAgents()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                HStack {
                    Image("ai-openclaw")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    Text(NSLocalizedString("settings.openclaw.title", comment: ""))
                        .font(Theme.Typography.headline())
                }

                Text(NSLocalizedString("settings.openclaw.description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - Messages

    private func successMessageSection(_ message: String) -> some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(message)
                    .font(Theme.Typography.body())
                    .foregroundColor(.green)
            }
        }
    }

    private func errorMessageSection(_ message: String) -> some View {
        Section {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(Theme.Typography.body())
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(NSLocalizedString("settings.openclaw.loading", comment: ""))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        Section {
            VStack(alignment: .center, spacing: Theme.spacing12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                Text(NSLocalizedString("settings.openclaw.no_agents", comment: ""))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Text(Brand.localized("settings.openclaw.no_agents_hint"))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacing16)
        }
    }

    // MARK: - Agents List

    private var agentsSection: some View {
        Section {
            ForEach(agents) { agent in
                agentRow(agent)
            }
        }
    }

    private func agentRow(_ agent: OpenClawAgent) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            // Email and status
            HStack {
                Text(agent.email)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Spacer()

                statusBadge(for: agent.status)
            }

            // Dates
            HStack {
                Text(String(format: NSLocalizedString("settings.openclaw.registered", comment: ""), formatDateString(agent.registeredAt)))
                    .font(Theme.Typography.caption2())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                if let lastActive = agent.lastActiveAt {
                    Text("·")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Text(String(format: NSLocalizedString("settings.openclaw.last_active", comment: ""), formatDateString(lastActive)))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }

                Spacer()
            }

            // Delete button
            HStack {
                Spacer()

                Button(role: .destructive, action: { agentToDelete = agent }) {
                    HStack(spacing: 4) {
                        if deletingId == agent.id {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(NSLocalizedString("settings.openclaw.delete_agent", comment: ""))
                    }
                    .font(Theme.Typography.caption1())
                }
                .disabled(deletingId != nil)
            }
            .padding(.top, Theme.spacing4)
        }
        .padding(.vertical, Theme.spacing4)
    }

    private func statusBadge(for status: String) -> some View {
        let (color, text) = statusInfo(for: status)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(Theme.Typography.caption2())
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    private func statusInfo(for status: String) -> (Color, String) {
        switch status {
        case "active":
            return (.green, NSLocalizedString("settings.openclaw.status.active", comment: ""))
        default:
            return (.gray, NSLocalizedString("settings.openclaw.status.idle", comment: ""))
        }
    }

    private func formatDateString(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .abbreviated
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        // Fallback: try without fractional seconds
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        if let date = fallbackFormatter.date(from: dateString) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .abbreviated
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return dateString
    }

    // MARK: - Connect Agent Section

    private var connectAgentSection: some View {
        Section {
            Button(action: {
                newAgentName = ""
                registerError = nil
                showRegisterSheet = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.accent)
                    Text(NSLocalizedString("settings.openclaw.connect_agent", comment: ""))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Register Agent Sheet

    private var registerAgentSheet: some View {
        NavigationStack {
            Form {
                // Agent name
                Section(
                    header: Text(NSLocalizedString("settings.openclaw.agent_name", comment: "")),
                    footer: Text(NSLocalizedString("settings.openclaw.agent_name_hint", comment: ""))
                ) {
                    TextField(
                        NSLocalizedString("settings.openclaw.agent_name_placeholder", comment: ""),
                        text: $newAgentName
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: newAgentName) { _, newValue in
                        // Enforce lowercase
                        let lowered = newValue.lowercased()
                        if lowered != newValue {
                            newAgentName = lowered
                        }
                    }
                }

                // Live preview
                Section {
                    if !newAgentName.isEmpty {
                        if isValidAgentName(newAgentName) {
                            Text(String(format: NSLocalizedString("settings.openclaw.agent_name_preview", comment: ""), newAgentName))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                        } else if Self.reservedNames.contains(newAgentName) {
                            Text(NSLocalizedString("settings.openclaw.agent_name_reserved", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(.red)
                        } else {
                            Text(NSLocalizedString("settings.openclaw.agent_name_invalid", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(.red)
                        }
                    }
                }

                // Error message
                if let error = registerError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(Theme.Typography.body())
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings.openclaw.register_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) {
                        showRegisterSheet = false
                    }
                    .disabled(isRegistering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRegistering {
                        ProgressView()
                    } else {
                        Button(NSLocalizedString("settings.openclaw.create_agent", comment: "")) {
                            _Concurrency.Task { await registerAgent() }
                        }
                        .disabled(!isValidAgentName(newAgentName))
                    }
                }
            }
        }
    }

    private func isValidAgentName(_ name: String) -> Bool {
        guard name.count >= 2, name.count <= 32 else { return false }
        guard !Self.reservedNames.contains(name) else { return false }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return Self.namePattern.firstMatch(in: name, range: range) != nil
    }

    // MARK: - Credentials Sheet

    private func credentialsSheet(_ result: OpenClawRegistrationResult) -> some View {
        NavigationStack {
            List {
                // Warning banner
                Section {
                    HStack(alignment: .top, spacing: Theme.spacing8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(NSLocalizedString("settings.openclaw.credentials_warning", comment: ""))
                            .font(Theme.Typography.body())
                            .foregroundColor(.orange)
                    }
                }

                // Credential rows
                Section {
                    credentialRow(
                        label: NSLocalizedString("settings.openclaw.credential.email", comment: ""),
                        value: result.agent.email,
                        fieldId: "email"
                    )

                    credentialRow(
                        label: NSLocalizedString("settings.openclaw.credential.client_id", comment: ""),
                        value: result.oauth.clientId,
                        fieldId: "clientId"
                    )

                    credentialRow(
                        label: NSLocalizedString("settings.openclaw.credential.client_secret", comment: ""),
                        value: result.oauth.clientSecret,
                        fieldId: "clientSecret",
                        isSecret: true
                    )

                    credentialRow(
                        label: NSLocalizedString("settings.openclaw.credential.token_endpoint", comment: ""),
                        value: result.config.tokenEndpoint,
                        fieldId: "tokenEndpoint"
                    )

                    credentialRow(
                        label: NSLocalizedString("settings.openclaw.credential.api_base", comment: ""),
                        value: result.config.apiBase,
                        fieldId: "apiBase"
                    )

                    credentialRow(
                        label: NSLocalizedString("settings.openclaw.credential.sse_endpoint", comment: ""),
                        value: result.config.sseEndpoint,
                        fieldId: "sseEndpoint"
                    )
                }
            }
            .navigationTitle(NSLocalizedString("settings.openclaw.credentials_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.done", comment: "")) {
                        registrationResult = nil
                    }
                }
            }
        }
    }

    private func credentialRow(label: String, value: String, fieldId: String, isSecret: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.caption2())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

            HStack {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isSecret ? .orange : (colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: {
                    UIPasteboard.general.string = value
                    copiedField = fieldId
                    _Concurrency.Task {
                        try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            if copiedField == fieldId {
                                copiedField = nil
                            }
                        }
                    }
                }) {
                    Image(systemName: copiedField == fieldId ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copiedField == fieldId ? .green : Theme.accent)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("settings.openclaw.about", comment: ""))
                    .font(Theme.Typography.subheadline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Text(Brand.localized("settings.openclaw.about_description"))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - Tip Section

    private var tipSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text(NSLocalizedString("settings.openclaw.tip_title", comment: ""))
                        .font(Theme.Typography.subheadline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }

                Text(NSLocalizedString("settings.openclaw.tip_description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - API Actions

    private func loadAgents() async {
        isLoading = true
        errorMessage = nil

        do {
            agents = try await apiClient.getOpenClawAgents()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func registerAgent() async {
        isRegistering = true
        registerError = nil

        do {
            let result = try await apiClient.registerOpenClawAgent(name: newAgentName.trimmingCharacters(in: .whitespaces))

            showRegisterSheet = false
            registrationResult = result

            // Reload agents list
            await loadAgents()

            successMessage = NSLocalizedString("settings.openclaw.agent_created", comment: "")

            // Clear success message after delay
            _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { successMessage = nil }
            }
        } catch {
            registerError = error.localizedDescription
        }

        isRegistering = false
    }

    private func deleteAgent(agentId: String) async {
        deletingId = agentId
        errorMessage = nil

        do {
            try await apiClient.deleteOpenClawAgent(id: agentId)
            agents.removeAll { $0.id == agentId }
            successMessage = NSLocalizedString("settings.openclaw.agent_deleted", comment: "")

            // Clear success message after delay
            _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { successMessage = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        deletingId = nil
    }
}

// MARK: - Identifiable conformance for registration result

extension OpenClawRegistrationResult: Identifiable {
    var id: String { agent.id }
}

#Preview {
    NavigationStack {
        OpenClawSettingsView()
    }
}
