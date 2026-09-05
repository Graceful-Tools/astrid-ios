//  AgentHub.swift
//  The ownership-first model behind the Agent Hub on iOS and Mac (AITD-297).
//
//  Mirrors astrid-web components/agent-hub.tsx. Per provider row the FIRST question is who owns
//  the runtime — Astrid, the user, or nobody — and only under "I run it" does a transport appear.
//  Storage stays the explicit four-state `AgentExecutionMode` (api | polling | webhook | off);
//  ownership is DERIVED for display and is never written to the server. Pull and push fail
//  differently, which is why the wire keeps polling and webhook distinct.

import Foundation

// MARK: - Ownership

/// Who operates the runtime. Presentation only — see the file header.
enum AgentOwnership: String, CaseIterable, Identifiable {
    /// Astrid runs it server-side with the provider's credential.
    case astrid
    /// The user runs it: a polling harness or a webhook server they host.
    case user
    /// Out of every picker; saved keys and settings are kept.
    case off

    var id: String { rawValue }

    init(mode: AgentExecutionMode) {
        switch mode {
        case .api: self = .astrid
        case .off: self = .off
        case .polling, .webhook: self = .user
        }
    }

    var localizedLabel: String {
        switch self {
        case .astrid:
            return String(format: NSLocalizedString("settings.agents.ownership.astrid", comment: ""), Brand.appName)
        case .user:
            return NSLocalizedString("settings.agents.ownership.user", comment: "")
        case .off:
            return NSLocalizedString("settings.agents.ownership.off", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .astrid: return "cloud"
        case .user: return "terminal"
        case .off: return "nosign"
        }
    }

    /// The mode to write when the user picks `ownership` while the row is in `current`.
    ///
    /// `nil` means nothing changes — in particular re-selecting "I run it" must not clobber a
    /// webhook transport the user already chose. Entering "I run it" from api/off writes
    /// `polling`, the web's default transport; the transport picker then refines it.
    static func modeToWrite(selecting ownership: AgentOwnership, current: AgentExecutionMode) -> AgentExecutionMode? {
        switch ownership {
        case .astrid:
            return current == .api ? nil : .api
        case .off:
            return current == .off ? nil : .off
        case .user:
            return AgentOwnership(mode: current) == .user ? nil : .polling
        }
    }
}

extension AgentExecutionMode {
    var ownership: AgentOwnership { AgentOwnership(mode: self) }

    /// What the UI assumes for a mailbox the server has not stored a mode for.
    static let unset: AgentExecutionMode = .polling
}

// MARK: - Transport under "I run it"

/// The transports offered once the user owns the runtime. `polling` and `webhook` are stored
/// modes; `sse` is not a per-provider mode at all — a Custom Agent is its own identity, so that
/// option hands over to the Custom Agents section.
enum AgentSelfTransport: String, CaseIterable, Identifiable {
    case polling
    case webhook
    case sse

    var id: String { rawValue }

    init?(mode: AgentExecutionMode) {
        switch mode {
        case .polling: self = .polling
        case .webhook: self = .webhook
        case .api, .off: return nil
        }
    }

    /// The execution mode this transport stores, or nil for the Custom Agent hand-off.
    var mode: AgentExecutionMode? {
        switch self {
        case .polling: return .polling
        case .webhook: return .webhook
        case .sse: return nil
        }
    }

    var localizedLabel: String {
        NSLocalizedString("settings.agents.transport.\(rawValue)", comment: "")
    }

    var systemImage: String {
        switch self {
        case .polling: return "terminal"
        case .webhook: return "point.3.connected.trianglepath.dotted"
        case .sse: return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Links out to the web

/// The web resources native links to rather than re-transcribes. The connection recipes are
/// generated from lib/agent-skill/astrid-queue-skill.ts and evolve; the docs page and the
/// generated skill download are the one owner of that copy.
enum AgentHubLinks {
    private static func clean(_ origin: String) -> String {
        origin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// "Connect my coding agent" — the per-harness connect / install / schedule / test recipes.
    static func loopsGuide(origin: String) -> URL? {
        URL(string: "\(clean(origin))/docs/loops")
    }

    /// The generated ASTRID_WORKFLOW.md skill a harness follows to work the queue.
    static func workflowDownload(origin: String) -> URL? {
        URL(string: "\(clean(origin))/api/downloads/ASTRID_WORKFLOW.md")
    }

    /// The web Agents settings page — where the GitHub App install/manage flow lives (`/api/github/*`
    /// is non-v1 and web-only, so native deep-links instead of reimplementing it).
    static func webAgentSettings(origin: String) -> URL? {
        URL(string: "\(clean(origin))/settings/agents")
    }

    /// Where a webhook server gets its own credentials.
    static func webAPIAccess(origin: String) -> URL? {
        URL(string: "\(clean(origin))/settings/api-access")
    }

    static let sdkPackage = URL(string: "https://www.npmjs.com/package/@gracefultools/astrid-sdk")!

    static let githubCopilotMCPDocs = URL(
        string: "https://docs.github.com/copilot/how-tos/copilot-on-github/customize-copilot/configure-mcp-servers"
    )!
}

// MARK: - Copilot cloud agent (GitHub.com) setup

/// The GitHub.com Copilot coding agent reaches Astrid over MCP with a user token. This produces
/// the same secret name and repository config as web components/github-copilot-mcp-setup.tsx,
/// so a user following either screen ends up with an identical repository setup.
enum CopilotCloudAgentSetup {
    static let tokenDescription = "GitHub Copilot cloud agent"

    /// `COPILOT_MCP_<WORDMARK>_TOKEN`, with anything outside [a-z0-9] folded to `_`.
    static func secretName(wordmark: String) -> String {
        let folded = wordmark.unicodeScalars.map { scalar -> String in
            let isAlphanumeric = (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
            return isAlphanumeric ? String(scalar).uppercased() : "_"
        }.joined()
        return "COPILOT_MCP_\(folded)_TOKEN"
    }

    /// The `mcpServers` JSON the user pastes into the repository's Copilot settings. Built with
    /// JSONSerialization rather than string interpolation so the wordmark and origin are escaped.
    static func mcpConfig(origin: String, wordmark: String) -> String {
        let cleanOrigin = origin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let server: [String: Any] = [
            "type": "http",
            "url": "\(cleanOrigin)/mcp",
            "headers": ["Authorization": "Bearer $\(secretName(wordmark: wordmark))"],
            "tools": ["*"],
        ]
        let root: [String: Any] = ["mcpServers": [wordmark.lowercased(): server]]
        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Custom Agent naming

/// The registration rule `POST /api/v1/custom-agents/register` enforces, checked client-side so
/// the sheet can explain a bad name before the round trip.
enum CustomAgentNaming {
    static let reservedNames: Set<String> = ["admin", "system", "test", "api", "support", "root", "openclaw"]

    private static let pattern = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9._-]{0,30}[a-z0-9]$")

    static func isReserved(_ name: String) -> Bool {
        reservedNames.contains(name)
    }

    static func isValid(_ name: String) -> Bool {
        guard name.count >= 2, name.count <= 32, !isReserved(name) else { return false }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return pattern.firstMatch(in: name, range: range) != nil
    }
}

// MARK: - Errors

enum AgentHubErrors {
    /// Some agent-hub writes are session-only on the server (webhook configuration, MCP user
    /// tokens): a 401/403 there means "do this from a signed-in web session", not "try again".
    static func requiresWebSession(_ error: Error) -> Bool {
        guard let apiError = error as? AstridAPIError else { return false }
        switch apiError {
        case .unauthorized: return true
        case .httpError(let status, _): return status == 401 || status == 403
        default: return false
        }
    }

    /// The server's `{ "error": "…" }` body when it sent one, else the error's own description.
    static func message(_ error: Error) -> String {
        if case .httpError(_, let body)? = error as? AstridAPIError,
           let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String {
            return message
        }
        return error.localizedDescription
    }
}
