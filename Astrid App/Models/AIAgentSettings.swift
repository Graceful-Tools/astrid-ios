import Foundation

// MARK: - AI Assistant Settings

struct AIAssistantSettings: Codable {
    var defaultAgentId: String?
    var preferredService: String?

    /// Whether the selected model is an on-device model (no API key / server needed)
    var isOnDeviceModel: Bool {
        defaultAgentId == kAppleFoundationModelId
    }
}

// MARK: - Available Agent

struct AvailableAgent: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let email: String
    let image: String?
    let service: String  // "claude", "openai", "gemini", "openclaw", "astrid"

    /// Whether this is a built-in service agent (vs OpenClaw/custom)
    var isBuiltIn: Bool {
        ["claude", "openai", "gemini", Self.defaultAssistantService].contains(service)
    }

    /// The `service` value the server uses for the default assistant identity.
    ///
    /// The assistant's email address is brand-derived on the server and can differ
    /// per deployment, so clients must identify it by `service` — never by matching
    /// its address. Task 97208a72.
    static let defaultAssistantService = "astrid"

    /// Whether this row is the default assistant rather than a specific model/provider.
    var isDefaultAssistant: Bool {
        service == Self.defaultAssistantService
    }

    /// Display-friendly service name
    var serviceDisplayName: String {
        switch service {
        case "claude": return "Claude"
        case "openai": return "OpenAI"
        case "gemini": return "Gemini"
        case "openclaw": return "OpenClaw"
        case Self.defaultAssistantService: return Brand.appName
        case "apple-fm": return "Apple Intelligence"
        default: return service.capitalized
        }
    }

    /// Local asset image name for the service brand icon, if available
    var serviceImageAsset: String? {
        switch service {
        case "claude": return "ai-claude"
        case "openai": return "ai-openai"
        case "gemini": return "ai-gemini"
        case "openclaw": return "ai-openclaw"
        default: return nil
        }
    }
}

// MARK: - All Built-in Models

/// Static list of all built-in model agents (shown even without API keys)
enum BuiltInModel: String, CaseIterable {
    case claude = "claude"
    case openai = "openai"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    var subtitle: String {
        switch self {
        case .claude: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google"
        }
    }

    var imageAsset: String {
        switch self {
        case .claude: return "ai-claude"
        case .openai: return "ai-openai"
        case .gemini: return "ai-gemini"
        }
    }
}

// MARK: - Agent Runtime Settings

    enum AgentExecutionMode: String, Codable, CaseIterable, Identifiable {
        case api
        case polling
        case webhook
        case off

        var id: String { rawValue }

        var localizedLabel: String {
            if self == .api {
                return String(
                    format: NSLocalizedString("settings.agents.mode.api", comment: ""),
                    Brand.appName
                )
            }
            return NSLocalizedString("settings.agents.mode.\(rawValue)", comment: "")
        }

        var systemImage: String {
            switch self {
            case .api: return "cloud"
            case .polling: return "terminal"
            case .webhook: return "point.3.connected.trianglepath.dotted"
            case .off: return "nosign"
            }
        }
    }

    struct AgentModeAgent: Codable, Equatable {
        let mailbox: String
        let email: String
        let mode: AgentExecutionMode
        let locked: Bool
    }

    struct AgentModesMeta: Codable, Equatable {
        let apiVersion: String
        let authSource: String
    }

    struct AgentModesResponse: Codable, Equatable {
        let agents: [AgentModeAgent]
        let modes: [String: AgentExecutionMode]
        let meta: AgentModesMeta?
    }

    struct UpdateAgentModeRequest: Codable, Equatable {
        let agent: String
        let mode: AgentExecutionMode
    }

    struct CopilotIntegrationStatus: Codable, Equatable {
        let connected: Bool
    }

    struct CopilotAuthorizationResponse: Codable, Equatable {
        let url: String
    }

    struct AgentRuntimeRow: Identifiable, Equatable {
        let id: String
        let label: String
        let modeMailbox: String
        let service: String
        let pollMailbox: String
        let imageAsset: String?
        let fallbackSystemImage: String
        let usesOAuth: Bool
        /// No server executor and no credential — the agent exists only as a CLI on the user's
        /// own machine, so "\(Brand.appName) runs it" is a button whose PUT the server rejects
        /// and there is no webhook to push work to. Mirrors web's `isHarnessOnly`, which reads
        /// the same harness registry the server rejects writes from.
        ///
        /// Keyed on the MODE MAILBOX, not the row: the Codex row is not harness-only, because
        /// the mode it writes is `openai`, which does have an executor.
        let isHarnessOnly: Bool

        func identityMailbox(for mode: AgentExecutionMode) -> String {
            id == "codex" && mode == .polling ? "codex" : modeMailbox
        }

        /// The ownership choices this row may offer. A harness-only agent has nobody but the
        /// user to run it, so "\(Brand.appName) runs it" is not among them.
        var availableOwnerships: [AgentOwnership] {
            isHarnessOnly ? [.user, .off] : AgentOwnership.allCases
        }

        /// The transports offered under "I run it". A harness-only agent has exactly one, so the
        /// picker is not a choice and the view does not draw it.
        var availableTransports: [AgentSelfTransport] {
            isHarnessOnly ? [.polling] : AgentSelfTransport.allCases
        }

        static let all: [AgentRuntimeRow] = [
            AgentRuntimeRow(
                id: "claude",
                label: "Claude",
                modeMailbox: "claude",
                service: "claude",
                pollMailbox: "claude",
                imageAsset: "ai-claude",
                fallbackSystemImage: "cpu",
                usesOAuth: false,
                isHarnessOnly: false
            ),
            AgentRuntimeRow(
                id: "codex",
                label: "Codex",
                modeMailbox: "openai",
                service: "openai",
                pollMailbox: "codex",
                imageAsset: "ai-openai",
                fallbackSystemImage: "cpu",
                usesOAuth: false,
                isHarnessOnly: false
            ),
            // Muse Code is Meta's terminal coding agent (August 2026) — a CLI the user runs, not
            // an API Astrid calls, so it has no key field and its identity never changes with the
            // mode. Web has it in lib/ai/harness-agents.ts (AWTD-937).
            AgentRuntimeRow(
                id: "muse",
                label: "Muse",
                modeMailbox: "muse",
                service: "muse",
                pollMailbox: "muse",
                imageAsset: "ai-muse",
                fallbackSystemImage: "terminal",
                usesOAuth: false,
                isHarnessOnly: true
            ),
            AgentRuntimeRow(
                id: "copilot",
                label: "GitHub Copilot",
                modeMailbox: "copilot",
                service: "copilot",
                pollMailbox: "copilot",
                imageAsset: "ai-copilot",
                fallbackSystemImage: "chevron.left.forwardslash.chevron.right",
                usesOAuth: true,
                isHarnessOnly: false
            ),
            AgentRuntimeRow(
                id: "gemini",
                label: "Gemini",
                modeMailbox: "gemini",
                service: "gemini",
                pollMailbox: "gemini",
                imageAsset: "ai-gemini",
                fallbackSystemImage: "cpu",
                usesOAuth: false,
                isHarnessOnly: false
            ),
        ]
    }

    struct AgentHarnessRecipe: Identifiable, Equatable {
        let id: String
        let name: String
        let steps: [String]
    }

    enum AgentHarnessRecipes {
        static func recipes(
            for mailbox: String,
            origin: String,
            serverName: String
        ) -> [AgentHarnessRecipe] {
            let cleanOrigin = origin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let mcpURL = "\(cleanOrigin)/mcp"
            let queuePrompt = "Call get_agent_queue with agent \"\(mailbox)\". Work every task it returns to completion, commenting progress on each one. If it answers empty:true, stop and say nothing is queued."

            switch mailbox {
            case "claude":
                return [
                    AgentHarnessRecipe(
                        id: "claude-code",
                        name: "Claude Code",
                        steps: [
                            "claude mcp add --transport http \(serverName) \(mcpURL)",
                            "# .claude/commands/\(serverName)-queue.md\n\(queuePrompt)",
                            "/loop 30m /\(serverName)-queue",
                            "*/30 * * * * cd ~/code/your-project && claude -p \"/\(serverName)-queue\" >> ~/\(serverName)-loop.log 2>&1",
                        ]
                    ),
                ]
            case "codex":
                return [
                    AgentHarnessRecipe(
                        id: "codex",
                        name: "Codex",
                        steps: [
                            "[mcp_servers.\(serverName)]\ncommand = \"npx\"\nargs = [\"-y\", \"mcp-remote\", \"\(mcpURL)\"]",
                            "*/30 * * * * cd ~/code/your-project && codex exec \"\(queuePrompt)\" >> ~/\(serverName)-loop.log 2>&1",
                        ]
                    ),
                ]
            case "muse":
                return [
                    AgentHarnessRecipe(
                        id: "muse",
                        name: "Muse Code",
                        steps: [
                            "muse mcp add \(serverName) --url \(mcpURL)\nmuse mcp login \(serverName)",
                            "[mcp_servers.\(serverName)]\ncommand = \"npx\"\nargs = [\"-y\", \"mcp-remote\", \"\(mcpURL)\"]",
                            // Muse parses options on the SUBCOMMAND, not the root, so the flag
                            // follows `exec` — `muse --disable-approval exec …` is not the same
                            // command and an unattended run would stop at the approval prompt.
                            "*/30 * * * * cd ~/code/your-project && muse exec \"\(queuePrompt)\" --disable-approval >> ~/\(serverName)-loop.log 2>&1",
                        ]
                    ),
                ]
            case "copilot":
                return [
                    AgentHarnessRecipe(
                        id: "copilot",
                        name: "Copilot CLI / VS Code",
                        steps: [
                            "copilot mcp add --transport http \(serverName) \(mcpURL)",
                            """
                            {
                              "servers": {
                                "\(serverName)": {
                                  "type": "http",
                                  "url": "\(mcpURL)"
                                }
                              }
                            }
                            """,
                            "*/30 * * * * cd ~/code/your-project && copilot -p \"\(queuePrompt)\" --allow-all-tools >> ~/\(serverName)-loop.log 2>&1",
                        ]
                    ),
                    AgentHarnessRecipe(
                        id: "github",
                        name: "GitHub Actions",
                        steps: [
                            """
                            # .github/workflows/\(serverName)-queue.yml
                            name: \(Brand.appName) queue
                            on:
                              schedule:
                                - cron: "*/30 * * * *"
                              workflow_dispatch:

                            jobs:
                              work-the-queue:
                                runs-on: ubuntu-latest
                                steps:
                                  - uses: actions/checkout@v4
                                  - name: Read the queue
                                    id: queue
                                    run: |
                                      curl -sS "\(cleanOrigin)/api/v1/agent-queue?agent=\(mailbox)" \\
                                        -H "X-OAuth-Token: ${{ secrets.ASTRID_TOKEN }}" > queue.json
                                      echo "empty=$(jq -r .empty queue.json)" >> "$GITHUB_OUTPUT"
                                  - name: Work it
                                    if: steps.queue.outputs.empty == 'false'
                                    run: echo "Hand queue.json to your agent step here"
                            """,
                        ]
                    ),
                ]
            case "gemini":
                return [
                    AgentHarnessRecipe(
                        id: "gemini",
                        name: "Gemini CLI",
                        steps: [
                            "{\n  \"mcpServers\": {\n    \"\(serverName)\": {\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"mcp-remote\", \"\(mcpURL)\"]\n    }\n  }\n}",
                            "*/30 * * * * cd ~/code/your-project && gemini -p \"\(queuePrompt)\" >> ~/\(serverName)-loop.log 2>&1",
                        ]
                    ),
                ]
            default:
                return []
            }
        }
    }
