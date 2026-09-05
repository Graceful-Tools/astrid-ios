//  CustomAgentsSettingsView.swift
//  Custom Agents on iOS (AITD-297): register (credentials shown once), list, edit the photo,
//  delete. A peer section of the Agent Hub, not a per-provider mode — a Custom Agent is its own
//  identity over OAuth + REST + SSE. Formerly OpenClawSettingsView; the server still stores these
//  as `openclaw_worker` and the `settings.openclaw.*` string keys were kept for that reason.

import SwiftUI
import PhotosUI

struct CustomAgentsSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var model = CustomAgentsModel()

    @State private var showRegisterSheet = false
    @State private var newAgentName = ""
    @State private var agentToDelete: CustomAgent?
    @State private var photoTarget: CustomAgent?
    @State private var photoSelection: PhotosPickerItem?
    @State private var copiedField: String?

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
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("settings.openclaw.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .swipeToDismiss()
        .task { await model.load() }
        .sheet(isPresented: $showRegisterSheet) { registerAgentSheet }
        .sheet(item: $model.registrationResult) { result in credentialsSheet(result) }
        .photosPicker(isPresented: Binding(
            get: { photoTarget != nil },
            set: { if !$0 { photoTarget = nil } }
        ), selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, item in
            guard let item, let agent = photoTarget else { return }
            photoSelection = nil
            photoTarget = nil
            _Concurrency.Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.8) {
                    await model.updatePhoto(agent, imageData: jpeg)
                }
            }
        }
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
                photoTarget = agent
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
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
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
                    TextField(NSLocalizedString("settings.openclaw.agent_name_placeholder", comment: ""), text: $newAgentName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: newAgentName) { _, value in
                            let lowered = value.lowercased()
                            if lowered != value { newAgentName = lowered }
                        }
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
            .navigationTitle(NSLocalizedString("settings.openclaw.register_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) { showRegisterSheet = false }
                        .disabled(model.isRegistering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isRegistering {
                        ProgressView()
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
            .navigationTitle(NSLocalizedString("settings.openclaw.credentials_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.done", comment: "")) { model.registrationResult = nil }
                }
            }
        }
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
                    UIPasteboard.general.string = value
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
}

#Preview {
    NavigationStack {
        CustomAgentsSettingsView()
    }
}
