//  AgentHubScreens.swift
//  The three Agent Hub sub-screens, written ONCE for both platforms (AITD-405).
//
//  AITD-398 shared the four Agent Hub *rows* into `AgentHubRows.swift`. The three screens above
//  them stayed twinned — `WebhookSettingsView`/`MacWebhookSettingsView`,
//  `CustomAgentsSettingsView`/`MacCustomAgentsView`,
//  `CopilotCloudAgentSetupView`/`MacCopilotCloudAgentView` — not because they disagreed about
//  anything, but because each lived on a file the other target excludes, so the only way to share
//  was to copy. The copies then drifted: the Mac webhook editor lost the agents hint, the
//  `ASTRID_WEBHOOK_SECRET=` line and the test response time; the Mac Custom Agents screen lost the
//  avatars and showed credentials as one blob instead of per-field copy rows.
//
//  Jon's call (2026-09-14): **share the iOS layout, keep the Mac's sheet chrome.** So the bodies
//  below are the iOS ones, and `MacAgentHubSheet` in `MacAgentHubView.swift` supplies the Mac's
//  header / Done / fixed frame around them.
//
//  This file must stay OFF the "Astrid Mac" membership exception list in project.pbxproj, or the
//  Mac loses all three screens again. `AgentHubTests.testAITD405_*` pins that.

import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Shared chrome

private extension View {
    /// Form chrome for a hub sub-screen. iOS pushes these as navigation detail, so it owns the
    /// title; the Mac presents them inside `MacAgentHubSheet`, which draws its own header.
    @ViewBuilder
    func agentHubScreenChrome(_ title: String) -> some View {
        #if os(macOS)
        self.formStyle(.grouped).macThemedSurface()
        #else
        self.scrollContentBackground(.hidden)
            .themedBackgroundPrimary()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Sheets nested inside a hub screen (register, credentials). macOS needs an explicit size;
    /// iOS sizes itself.
    @ViewBuilder
    func agentHubNestedSheetSize() -> some View {
        #if os(macOS)
        self.frame(width: 480, height: 420)
        #else
        self
        #endif
    }
}

// MARK: - Webhook transport

/// The webhook transport editor — mirrors astrid-web's `components/webhook-settings-manager.tsx`
/// over the shared `WebhookSettingsModel`.
struct WebhookSettingsScreen: View {
    static var title: String { NSLocalizedString("settings.agents.transport.webhook", comment: "") }

    @Environment(\.openURL) private var openURL
    @StateObject private var model = WebhookSettingsModel()
    @State private var confirmRemove = false

    var body: some View {
        Form {
            if model.isLoading {
                Section {
                    HStack { ProgressView(); Text(NSLocalizedString("settings.agents.loading", comment: "")) }
                }
            } else {
                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.red)
                        if model.requiresWebSession {
                            WebSessionRequiredRow()
                        }
                    }
                }

                if let secret = model.newSecret {
                    Section {
                        Label(NSLocalizedString("settings.agents.webhook.secret_warning", comment: ""), systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.orange)
                        CopyableCodeBlock(code: secret)
                        CopyableCodeBlock(code: "ASTRID_WEBHOOK_SECRET=\(secret)")
                    } header: {
                        Text(NSLocalizedString("settings.agents.webhook.secret_title", comment: ""))
                    }
                }

                editorSection

                if model.settings.configured {
                    statusSection
                }
            }
        }
        .agentHubScreenChrome(Self.title)
        .task { await model.load() }
        .confirmationDialog(
            NSLocalizedString("settings.agents.webhook.remove_confirm", comment: ""),
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("settings.agents.webhook.remove", comment: ""), role: .destructive) {
                _Concurrency.Task { await model.delete() }
            }
        }
    }

    private var editorSection: some View {
        Section {
            urlField

            Toggle(NSLocalizedString("settings.agents.webhook.enabled", comment: ""), isOn: $model.enabled)

            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("settings.agents.webhook.agents", comment: ""))
                Text(NSLocalizedString("settings.agents.webhook.agents_hint", comment: ""))
                    .font(Theme.Typography.caption2())
                    .foregroundStyle(.secondary)
                ForEach(model.availableAgents, id: \.self) { agent in
                    Toggle(isOn: Binding(
                        get: { model.selectedAgents.contains(agent) },
                        set: { _ in model.toggleAgent(agent) }
                    )) {
                        Text(WebhookAgentLabel.label(for: agent))
                    }
                }
                if model.selectedAgents.isEmpty {
                    Text(NSLocalizedString("settings.agents.webhook.no_agents", comment: ""))
                        .font(Theme.Typography.caption2())
                        .foregroundStyle(.orange)
                }
            }

            if model.settings.configured, model.settings.hasSecret == true {
                Toggle(NSLocalizedString("settings.agents.webhook.regenerate", comment: ""), isOn: $model.regenerateSecret)
            }

            Button {
                _Concurrency.Task { await model.save() }
            } label: {
                HStack {
                    Label(
                        NSLocalizedString(
                            model.settings.configured ? "settings.agents.webhook.update" : "settings.agents.webhook.save",
                            comment: ""
                        ),
                        systemImage: "checkmark"
                    )
                    if model.isSaving { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(!model.canSave)

            if model.settings.configured {
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label(NSLocalizedString("settings.agents.webhook.remove", comment: ""), systemImage: "trash")
                }
                .disabled(model.isSaving)
            }
        } footer: {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(String(format: NSLocalizedString("settings.agents.webhook.url_hint", comment: ""), Brand.appName))
                if let api = AgentHubLinks.webAPIAccess(origin: Constants.API.baseURL) {
                    Button(NSLocalizedString("settings.agents.open_web", comment: "")) { openURL(api) }
                        .font(Theme.Typography.caption2())
                }
            }
        }
    }

    /// The URL field is the one place the two platforms genuinely differ: the keyboard hints are
    /// UIKit-only, and the Mac wants a bordered field inside a grouped Form.
    private var urlField: some View {
        let field = TextField(
            NSLocalizedString("settings.agents.webhook.url", comment: ""),
            text: $model.webhookUrl,
            prompt: Text(verbatim: "https://your-server.com/webhook")
        )
        #if os(macOS)
        return field.textFieldStyle(.roundedBorder)
        #else
        return field
            .keyboardType(.URL)
            .textContentType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #endif
    }

    private var statusSection: some View {
        Section(NSLocalizedString("settings.agents.webhook.status", comment: "")) {
            HStack {
                Circle()
                    .fill(model.settings.enabled == true ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(NSLocalizedString(
                    model.settings.enabled == true ? "settings.agents.webhook.active" : "settings.agents.webhook.disabled",
                    comment: ""
                ))
                Spacer()
                let failures = model.settings.failureCount ?? 0
                Text(failures > 0
                     ? String(format: NSLocalizedString("settings.agents.webhook.failures", comment: ""), failures)
                     : NSLocalizedString("settings.agents.webhook.no_failures", comment: ""))
                    .font(Theme.Typography.caption2())
                    .foregroundStyle(failures > 0 ? .red : .secondary)
            }
            if let lastFired = model.settings.lastFiredAt {
                Text(String(format: NSLocalizedString("settings.agents.webhook.last_fired", comment: ""), lastFired))
                    .font(Theme.Typography.caption2())
                    .foregroundStyle(.secondary)
            }
            Button {
                _Concurrency.Task { await model.test() }
            } label: {
                HStack {
                    Label(NSLocalizedString("settings.agents.webhook.test", comment: ""), systemImage: "paperplane")
                    if model.isTesting { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(model.isTesting || model.settings.enabled != true)

            if let result = model.testResult {
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Label(result.message ?? (result.success ? "OK" : "Failed"),
                          systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    if let responseTime = result.responseTime {
                        Text(String(format: NSLocalizedString("settings.agents.webhook.test_response", comment: ""), responseTime))
                            .font(Theme.Typography.caption2())
                            .foregroundStyle(.secondary)
                    }
                    if let error = result.error {
                        Text(error)
                            .font(Theme.Typography.caption2())
                            .foregroundStyle(.red)
                    }
                }
                .font(Theme.Typography.caption1())
            }
        }
    }
}

// MARK: - Copilot cloud agent (GitHub.com)

/// Token + repository MCP configuration for the Copilot coding agent that runs on GitHub.com.
struct CopilotCloudAgentScreen: View {
    static var title: String { NSLocalizedString("settings.agents.copilot_cloud.title", comment: "") }

    @Environment(\.openURL) private var openURL
    @StateObject private var model = CopilotCloudAgentModel()

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
                    CopyableCodeBlock(code: token)
                }
                Section(NSLocalizedString("settings.agents.copilot_cloud.config", comment: "")) {
                    Text(NSLocalizedString("settings.agents.copilot_cloud.config_step", comment: ""))
                        .font(Theme.Typography.caption1())
                    CopyableCodeBlock(code: model.config)
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
                            if model.isCreating { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(model.isCreating)
                }
            }
        }
        .agentHubScreenChrome(Self.title)
    }
}

// MARK: - Custom Agents

/// Register (credentials shown once), list, re-photo and delete Custom Agents. A peer section of
/// the Agent Hub, not a per-provider mode — a Custom Agent is its own identity over OAuth + REST +
/// SSE. Formerly OpenClawSettingsView; the server still stores these as `openclaw_worker`, which is
/// why the `settings.openclaw.*` string keys were kept.
struct CustomAgentsScreen: View {
    static var title: String { NSLocalizedString("settings.openclaw.title", comment: "") }

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = CustomAgentsModel()

    @State private var showRegisterSheet = false
    @State private var newAgentName = ""
    @State private var agentToDelete: CustomAgent?
    @State private var copiedField: String?
    #if os(iOS)
    @State private var photoTarget: CustomAgent?
    @State private var photoSelection: PhotosPickerItem?
    #endif

    var body: some View {
        Form {
            headerSection

            if let successMessage = model.successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.body())
                        .foregroundColor(.green)
                }
            }
            if let errorMessage = model.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.body())
                        .foregroundColor(.red)
                }
            }

            if model.isLoading {
                Section {
                    HStack {
                        ProgressView().tint(Theme.accent)
                        Text(NSLocalizedString("settings.openclaw.loading", comment: ""))
                            .font(Theme.Typography.body())
                            .foregroundColor(secondaryColor)
                    }
                }
            } else if model.agents.isEmpty {
                Section {
                    VStack(spacing: Theme.spacing12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 36))
                            .foregroundColor(secondaryColor)
                        Text(NSLocalizedString("settings.openclaw.no_agents", comment: ""))
                            .font(Theme.Typography.subheadline())
                            .foregroundColor(primaryColor)
                        Text(Brand.localized("settings.openclaw.no_agents_hint"))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(secondaryColor)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing16)
                }
            } else {
                Section(NSLocalizedString("settings.openclaw.section", comment: "")) {
                    ForEach(model.agents) { agent in
                        agentRow(agent)
                    }
                }
            }

            Section {
                Button {
                    newAgentName = ""
                    model.registerErrorMessage = nil
                    showRegisterSheet = true
                } label: {
                    Label(NSLocalizedString("settings.openclaw.connect_agent", comment: ""), systemImage: "plus.circle.fill")
                        .foregroundColor(Theme.accent)
                }
            }

            infoSection
            tipSection
        }
        .agentHubScreenChrome(Self.title)
        .swipeBackToDismissOnIOS()
        .task { await model.load() }
        .sheet(isPresented: $showRegisterSheet) { registerAgentSheet }
        .sheet(item: $model.registrationResult) { result in credentialsSheet(result) }
        .photoPickerIfAvailable(target: photoPickerBinding, selection: photoSelectionBinding)
        .confirmationDialog(
            NSLocalizedString("settings.openclaw.delete_agent", comment: ""),
            isPresented: Binding(get: { agentToDelete != nil }, set: { if !$0 { agentToDelete = nil } }),
            titleVisibility: .visible,
            presenting: agentToDelete
        ) { agent in
            Button(NSLocalizedString("settings.openclaw.delete_agent", comment: ""), role: .destructive) {
                _Concurrency.Task { await model.delete(agent) }
            }
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
        } message: { agent in
            Text(String(format: NSLocalizedString("settings.openclaw.delete_confirm", comment: ""), agent.email))
        }
    }

    private var primaryColor: Color { colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary }
    private var secondaryColor: Color { colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                HStack {
                    Image("ai-openclaw")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    Text(NSLocalizedString("settings.openclaw.title", comment: ""))
                        .font(Theme.Typography.subheadline())
                        .foregroundColor(primaryColor)
                }
                Text(NSLocalizedString("settings.openclaw.description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(secondaryColor)
            }
        }
    }

    private func agentRow(_ agent: CustomAgent) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing12) {
            Button {
                selectPhoto(for: agent)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    agentAvatar(agent)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 9))
                        .padding(3)
                        .background(Theme.accent, in: Circle())
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.updatingPhotoId == agent.id)

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.email)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(primaryColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Theme.spacing8) {
                    let (color, label) = statusBadge(agent.status)
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label).font(Theme.Typography.caption2()).foregroundColor(secondaryColor)
                }
                Text(String(format: NSLocalizedString("settings.openclaw.registered", comment: ""), formatDateString(agent.registeredAt)))
                    .font(Theme.Typography.caption2())
                    .foregroundColor(secondaryColor)
                if let lastActive = agent.lastActiveAt {
                    Text(String(format: NSLocalizedString("settings.openclaw.last_active", comment: ""), formatDateString(lastActive)))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(secondaryColor)
                }
            }

            Spacer()

            if model.deletingId == agent.id || model.updatingPhotoId == agent.id {
                ProgressView().tint(Theme.accent)
            } else {
                Button(role: .destructive) {
                    agentToDelete = agent
                } label: {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func agentAvatar(_ agent: CustomAgent) -> some View {
        if let image = agent.image, !image.isEmpty, let url = resolvedImageURL(image) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image("ai-openclaw").resizable().aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            Image("ai-openclaw")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        }
    }

    private func resolvedImageURL(_ image: String) -> URL? {
        var path = image
        if path.hasSuffix(".svg") { path = path.replacingOccurrences(of: ".svg", with: ".png") }
        if path.hasPrefix("http") { return URL(string: path) }
        let base = Constants.API.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + path)
    }

    private func statusBadge(_ status: String) -> (Color, String) {
        status == "active"
            ? (.green, NSLocalizedString("settings.openclaw.status.active", comment: ""))
            : (.gray, NSLocalizedString("settings.openclaw.status.idle", comment: ""))
    }

    private func formatDateString(_ iso: String) -> String {
        // Fractional-then-plain was hand-rolled here; it is WireDate's job now (AITD-404).
        guard let date = WireDate.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("settings.openclaw.about", comment: ""))
                    .font(Theme.Typography.subheadline())
                    .foregroundColor(primaryColor)
                Text(Brand.localized("settings.openclaw.about_description"))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(secondaryColor)
            }
        }
    }

    private var tipSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Label(NSLocalizedString("settings.openclaw.tip_title", comment: ""), systemImage: "lightbulb.fill")
                    .font(Theme.Typography.subheadline())
                    .foregroundColor(primaryColor)
                Text(NSLocalizedString("settings.openclaw.tip_description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(secondaryColor)
            }
        }
    }

    // MARK: - Register sheet

    private var registerAgentSheet: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text(NSLocalizedString("settings.openclaw.agent_name", comment: "")),
                    footer: Text(NSLocalizedString("settings.openclaw.agent_name_hint", comment: ""))
                ) {
                    agentNameField
                }

                Section {
                    if !newAgentName.isEmpty {
                        if CustomAgentNaming.isValid(newAgentName) {
                            Text(String(format: NSLocalizedString("settings.openclaw.agent_name_preview", comment: ""), newAgentName))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                        } else if CustomAgentNaming.isReserved(newAgentName) {
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

                if let error = model.registerErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.body())
                            .foregroundColor(.red)
                    }
                }
            }
            .agentHubScreenChrome(NSLocalizedString("settings.openclaw.register_title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) { showRegisterSheet = false }
                        .disabled(model.isRegistering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isRegistering {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(NSLocalizedString("settings.openclaw.create_agent", comment: "")) {
                            _Concurrency.Task {
                                if await model.register(name: newAgentName) {
                                    showRegisterSheet = false
                                }
                            }
                        }
                        .disabled(!CustomAgentNaming.isValid(newAgentName))
                    }
                }
            }
        }
        .agentHubNestedSheetSize()
    }

    private var agentNameField: some View {
        let field = TextField(NSLocalizedString("settings.openclaw.agent_name_placeholder", comment: ""), text: $newAgentName)
            .onChange(of: newAgentName) { _, value in
                let lowered = value.lowercased()
                if lowered != value { newAgentName = lowered }
            }
        #if os(macOS)
        return field.textFieldStyle(.roundedBorder)
        #else
        return field
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #endif
    }

    // MARK: - Credentials sheet (shown once)

    private func credentialsSheet(_ result: CustomAgentRegistrationResult) -> some View {
        NavigationStack {
            List {
                Section {
                    Label(NSLocalizedString("settings.openclaw.credentials_warning", comment: ""), systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.body())
                        .foregroundColor(.orange)
                }
                Section {
                    credentialRow(NSLocalizedString("settings.openclaw.credential.email", comment: ""), result.agent.email, "email")
                    credentialRow(NSLocalizedString("settings.openclaw.credential.client_id", comment: ""), result.oauth.clientId, "clientId")
                    credentialRow(NSLocalizedString("settings.openclaw.credential.client_secret", comment: ""), result.oauth.clientSecret, "clientSecret", isSecret: true)
                    credentialRow(NSLocalizedString("settings.openclaw.credential.token_endpoint", comment: ""), result.config.tokenEndpoint, "tokenEndpoint")
                    credentialRow(NSLocalizedString("settings.openclaw.credential.api_base", comment: ""), result.config.apiBase, "apiBase")
                    credentialRow(NSLocalizedString("settings.openclaw.credential.sse_endpoint", comment: ""), result.config.sseEndpoint, "sseEndpoint")
                }
            }
            .agentHubScreenChrome(NSLocalizedString("settings.openclaw.credentials_title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.done", comment: "")) { model.registrationResult = nil }
                }
            }
        }
        .agentHubNestedSheetSize()
    }

    private func credentialRow(_ label: String, _ value: String, _ fieldId: String, isSecret: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.caption2())
                .foregroundColor(secondaryColor)
            HStack {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isSecret ? .orange : primaryColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    PlatformPasteboard.copy(value)
                    copiedField = fieldId
                    _Concurrency.Task {
                        try? await _Concurrency.Task.sleep(for: .seconds(2))
                        if copiedField == fieldId { copiedField = nil }
                    }
                } label: {
                    Image(systemName: copiedField == fieldId ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copiedField == fieldId ? .green : Theme.accent)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Picking an agent photo

    // The only mechanic that has no shared spelling: iOS goes through PhotosUI (which needs the
    // photo library entitlement), the Mac through an NSOpenPanel. Both end at the same
    // `model.updatePhoto(_:imageData:)` with JPEG at 0.8.

    #if os(iOS)
    private var photoPickerBinding: Binding<CustomAgent?> {
        Binding(get: { photoTarget }, set: { photoTarget = $0 })
    }

    private var photoSelectionBinding: Binding<PhotosPickerItem?> {
        Binding(get: { photoSelection }, set: { item in
            photoSelection = nil
            guard let item, let agent = photoTarget else { return }
            photoTarget = nil
            _Concurrency.Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.8) {
                    await model.updatePhoto(agent, imageData: jpeg)
                }
            }
        })
    }

    private func selectPhoto(for agent: CustomAgent) {
        photoTarget = agent
    }
    #else
    private var photoPickerBinding: Binding<CustomAgent?> { .constant(nil) }
    private var photoSelectionBinding: Binding<Int?> { .constant(nil) }

    private func selectPhoto(for agent: CustomAgent) {
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
    #endif
}

// MARK: - The two iOS-only modifiers, spelled once

private extension View {
    /// The back-swipe affordance exists only on iOS — `View+SwipeToDismiss.swift` is itself on the
    /// Mac target's exception list, so this cannot simply be called unguarded.
    @ViewBuilder
    func swipeBackToDismissOnIOS() -> some View {
        #if os(iOS)
        self.swipeToDismiss()
        #else
        self
        #endif
    }
}

#if os(iOS)
private extension View {
    func photoPickerIfAvailable(target: Binding<CustomAgent?>, selection: Binding<PhotosPickerItem?>) -> some View {
        photosPicker(
            isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } }),
            selection: selection,
            matching: .images
        )
    }
}
#else
private extension View {
    /// The Mac picks its photo through an NSOpenPanel raised from the row button, so there is no
    /// presenter to attach here.
    func photoPickerIfAvailable(target: Binding<CustomAgent?>, selection: Binding<Int?>) -> some View { self }
}
#endif

#if os(iOS)
#Preview("Webhook") { NavigationStack { WebhookSettingsScreen() } }
#Preview("Custom Agents") { NavigationStack { CustomAgentsScreen() } }
#endif
