//  MacAIKeysView.swift
//  Astrid for Mac — AI API keys + OpenClaw agents (Task f8687dfb). Over the shared
//  RemoteResourceService, mirroring iOS AIAPIKeyManagerView + OpenClawSettingsView.

#if os(macOS)
import SwiftUI

struct MacAIKeysView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keys: [String: AIAPIKeyStatus] = [:]
    @State private var drafts: [String: String] = [:]
    @State private var busy: String?               // serviceId being saved/tested
    @State private var agents: [OpenClawAgent] = []
    @State private var newAgentName = ""
    @State private var credentials: String?         // one-time OpenClaw credentials to show

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(NSLocalizedString("mac.ai_keys_agents", comment: "")).font(.headline); Spacer(); Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return) }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            Form {
                Section(NSLocalizedString("mac.api_keys", comment: "")) {
                    ForEach(MacAIKeys.providers) { p in providerRow(p) }
                }
                Section(NSLocalizedString("settings.openclaw.section", comment: "")) {
                    ForEach(agents) { a in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(a.agentName.isEmpty ? a.name : a.agentName)
                                Text(a.status).font(.caption).foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { deleteAgent(a) }
                        }
                    }
                    HStack {
                        TextField(NSLocalizedString("mac.new_agent_name", comment: ""), text: $newAgentName).textFieldStyle(.roundedBorder)
                        Button(NSLocalizedString("mac.register", comment: "")) { registerAgent() }
                            .disabled(newAgentName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .formStyle(.grouped).macThemedSurface()
        }
        .frame(width: 480, height: 500)
        .task { await load() }
        .alert("OpenClaw credentials (save these now)", isPresented: Binding(
            get: { credentials != nil }, set: { if !$0 { credentials = nil } })) {
            Button(NSLocalizedString("actions.copy", comment: "")) { if let c = credentials { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c, forType: .string) } }
            Button(NSLocalizedString("actions.done", comment: ""), role: .cancel) {}
        } message: { Text(credentials ?? "") }
    }

    @ViewBuilder private func providerRow(_ p: MacAIKeys.Provider) -> some View {
        let status = keys[p.id]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(p.name)
                Spacer()
                Text(MacAIKeys.statusText(hasKey: status?.hasKey ?? false, preview: status?.keyPreview, isValid: status?.isValid))
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
            HStack {
                SecureField("API key", text: Binding(get: { drafts[p.id] ?? "" }, set: { drafts[p.id] = $0 }))
                    .textFieldStyle(.roundedBorder)
                Button(NSLocalizedString("actions.save", comment: "")) { save(p.id) }.disabled((drafts[p.id] ?? "").isEmpty || busy == p.id)
                if status?.hasKey == true {
                    Button(NSLocalizedString("settings.reminders.test", comment: "")) { test(p.id) }.disabled(busy == p.id)
                    Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { deleteKey(p.id) }
                }
                if busy == p.id { ProgressView().controlSize(.small) }
            }
        }
    }

    private func load() async {
        keys = (try? await RemoteResourceService.shared.getAIAPIKeys())?.keys ?? [:]
        agents = (try? await RemoteResourceService.shared.getOpenClawAgents()) ?? []
    }

    private func save(_ id: String) {
        let key = drafts[id] ?? ""; guard !key.isEmpty else { return }
        busy = id
        MacActions.perform("Save API key") {
            defer { busy = nil }
            _ = try await RemoteResourceService.shared.saveAIAPIKey(serviceId: id, apiKey: key)
            drafts[id] = ""
            keys = (try? await RemoteResourceService.shared.getAIAPIKeys())?.keys ?? keys
        }
    }
    private func test(_ id: String) {
        busy = id
        MacActions.perform("Test API key") {
            defer { busy = nil }
            _ = try await RemoteResourceService.shared.testAIAPIKey(serviceId: id)
            keys = (try? await RemoteResourceService.shared.getAIAPIKeys())?.keys ?? keys
        }
    }
    private func deleteKey(_ id: String) {
        MacActions.perform("Delete API key") {
            _ = try await RemoteResourceService.shared.deleteAIAPIKey(serviceId: id)
            keys = (try? await RemoteResourceService.shared.getAIAPIKeys())?.keys ?? keys
        }
    }
    private func registerAgent() {
        let name = newAgentName.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }
        newAgentName = ""
        MacActions.perform("Register agent") {
            let result = try await RemoteResourceService.shared.registerOpenClawAgent(name: name)
            credentials = "Client ID: \(result.oauth.clientId)\nClient Secret: \(result.oauth.clientSecret)"
            agents = (try? await RemoteResourceService.shared.getOpenClawAgents()) ?? agents
        }
    }
    private func deleteAgent(_ a: OpenClawAgent) {
        MacActions.perform("Delete agent") {
            try await RemoteResourceService.shared.deleteOpenClawAgent(id: a.id)
            agents = (try? await RemoteResourceService.shared.getOpenClawAgents()) ?? agents
        }
    }
}
#endif
