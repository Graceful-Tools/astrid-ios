//  WebhookSettingsView.swift
//  The webhook transport editor on iOS (AITD-297) — mirrors astrid-web's
//  components/webhook-settings-manager.tsx over the shared `WebhookSettingsModel`.

import SwiftUI

struct WebhookSettingsView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var model = WebhookSettingsModel()
    @State private var confirmRemove = false
    @State private var copiedField: String?

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
                        CopyableCodeBlock(code: secret, id: "secret", copiedField: $copiedField)
                        CopyableCodeBlock(code: "ASTRID_WEBHOOK_SECRET=\(secret)", id: "env", copiedField: $copiedField)
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
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("settings.agents.transport.webhook", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
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
            TextField(
                NSLocalizedString("settings.agents.webhook.url", comment: ""),
                text: $model.webhookUrl,
                prompt: Text(verbatim: "https://your-server.com/webhook")
            )
            .keyboardType(.URL)
            .textContentType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

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
                        Text(Self.label(for: agent))
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
                    if model.isSaving { Spacer(); ProgressView() }
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
                    if model.isTesting { Spacer(); ProgressView() }
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

    /// The same labels the web's agent chips use; the mailbox is the fallback.
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

#Preview {
    NavigationStack {
        WebhookSettingsView()
    }
}
