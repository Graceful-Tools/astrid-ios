//  AgentHubRows.swift
//  Astrid — the Agent Hub pieces BOTH platforms show (AITD-398).
//
//  `AgentHubModel` was already shared, but the view layer under it was written twice:
//  `Astrid App/Views/Settings/AgentHubView.swift` and `Astrid Mac/Views/MacAgentHubView.swift`
//  each carried its own copy of the session-required row, the copyable code block, the GitHub
//  connection section and the agent-label map — the same strings, the same links and the same
//  load path, differing only in chrome.
//
//  They live HERE rather than in either view file because both of those are on the Mac target's
//  membership-exception list; `Core/Platform/` is inside the synchronized group the Mac target
//  compiles, so a file added here joins both targets with no project.pbxproj edit.
//
//  Rule for this file: shared state, shared strings, shared links. Where the two platforms
//  genuinely want different chrome, branch on `#if os(macOS)` INSIDE the one struct — never by
//  growing a second one.

import SwiftUI

// MARK: - "Do this on the web"

/// For the writes the server only accepts from an interactive web session.
struct WebSessionRequiredRow: View {
    private var webSettingsURL: URL? { AgentHubLinks.webAgentSettings(origin: Constants.API.baseURL) }

    var body: some View {
        #if os(macOS)
        HStack {
            message
            Spacer()
            if let webSettingsURL {
                Button(NSLocalizedString("settings.agents.open_web", comment: "")) {
                    PlatformApplication.open(webSettingsURL)
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            message
            if let webSettingsURL {
                Button {
                    PlatformApplication.open(webSettingsURL)
                } label: {
                    Label(NSLocalizedString("settings.agents.open_web", comment: ""), systemImage: "safari")
                }
            }
        }
        #endif
    }

    private var message: some View {
        Text(NSLocalizedString("settings.agents.session_required", comment: ""))
            .font(Theme.Typography.caption1())
            .foregroundStyle(Theme.warning)
    }
}

// MARK: - Copyable code

/// Monospaced, selectable code with a copy button and a two-second "Copied" acknowledgement.
///
/// The acknowledgement is local state on purpose. iOS used to thread a shared
/// `@Binding copiedField: String?` through every block, whose only visible effect was that
/// copying the second block silently cleared the first one's tick — bookkeeping, not a feature.
struct CopyableCodeBlock: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.spacing8) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                PlatformPasteboard.copy(code)
                copied = true
                _Concurrency.Task {
                    try? await _Concurrency.Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(
                    NSLocalizedString(copied ? "settings.agents.copied" : "actions.copy", comment: ""),
                    systemImage: copied ? "checkmark" : "doc.on.doc"
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

// MARK: - GitHub App connection (account-level, server-run only)

/// Only "Astrid runs it" needs this: server-run agents create branches and PRs through the
/// GitHub App. The install/manage flow is web-only (`/api/github/*`), so this shows status and
/// deep-links out rather than reimplementing it.
struct GitHubConnectionSection: View {
    @State private var status: GitHubStatusResponse?
    @State private var failed = false

    private var manageURL: URL? { AgentHubLinks.webAgentSettings(origin: Constants.API.baseURL) }
    private var isConnected: Bool { status?.isGitHubConnected == true }

    var body: some View {
        section
            .task {
                do {
                    status = try await RemoteResourceService.shared.getGitHubStatus()
                } catch {
                    failed = true
                }
            }
    }

    @ViewBuilder
    private var section: some View {
        #if os(macOS)
        Section(NSLocalizedString("settings.agents.github.title", comment: "")) {
            Text(String(format: NSLocalizedString("settings.agents.github.description", comment: ""), Brand.appName))
                .font(Theme.Typography.caption1())
                .foregroundStyle(Theme.textMuted)
            HStack {
                Circle()
                    .fill(isConnected ? Theme.success : Theme.textMuted)
                    .frame(width: 8, height: 8)
                statusText
                Spacer()
                manageButton
            }
        }
        #else
        Section {
            HStack {
                Image(systemName: isConnected ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(isConnected ? .green : .secondary)
                statusText
                Spacer()
                manageButton
                    .font(Theme.Typography.caption1())
            }
        } header: {
            Label(NSLocalizedString("settings.agents.github.title", comment: ""),
                  systemImage: "chevron.left.forwardslash.chevron.right")
        } footer: {
            Text(String(format: NSLocalizedString("settings.agents.github.description", comment: ""), Brand.appName))
        }
        #endif
    }

    @ViewBuilder
    private var statusText: some View {
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
    }

    @ViewBuilder
    private var manageButton: some View {
        if let manageURL {
            Button(NSLocalizedString("settings.agents.github.manage", comment: "")) {
                PlatformApplication.open(manageURL)
            }
        }
    }
}

// MARK: - Agent labels

/// The same labels the web's agent chips use; the mailbox is the fallback.
///
/// Both webhook editors list the agents a webhook fires for, and both are on the other target's
/// exception list, which is the only reason this map was ever written twice.
enum WebhookAgentLabel {
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
