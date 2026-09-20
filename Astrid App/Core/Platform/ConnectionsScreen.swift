//  ConnectionsScreen.swift
//  Everything that can act as this account, with a way to stop each one — written once for
//  iOS and Mac, like the Agent Hub sub-screens (AITD-405).
//
//  Native twin of astrid-web components/connections-list.tsx over the same endpoint. The list is
//  the whole screen: the developer console (hand-made OAuth apps, the API tester) stays on the
//  web, reachable from the footer, because a scope matrix is not a phone-sized decision.

import SwiftUI

// MARK: - The list

struct ConnectionsScreen: View {
    static var title: String { NSLocalizedString("settings.connections.title", comment: "") }

    @Environment(\.openURL) private var openURL
    @StateObject private var model = ConnectionsModel()
    @State private var pendingRevoke: Connection?

    var body: some View {
        Form {
            Section {
                Text(NSLocalizedString("settings.connections.subtitle", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundStyle(.secondary)
            }

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

                if model.connections.isEmpty {
                    Section {
                        Text(NSLocalizedString("settings.connections.empty", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(model.sections, id: \.kind) { section in
                    Section(section.kind.localizedLabel) {
                        ForEach(section.rows) { row in
                            ConnectionRow(connection: row, isRevoking: model.revokingID == row.id) {
                                pendingRevoke = row
                            }
                        }
                    }
                }
            }

            Section {
                if let web = AgentHubLinks.webConnections(origin: Constants.API.baseURL) {
                    Button {
                        openURL(web)
                    } label: {
                        Label(NSLocalizedString("settings.connections.developer_web", comment: ""), systemImage: "safari")
                    }
                }
            }
        }
        .agentHubScreenChrome(Self.title)
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog(
            NSLocalizedString("settings.connections.revoke", comment: ""),
            isPresented: Binding(
                get: { pendingRevoke != nil },
                set: { if !$0 { pendingRevoke = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRevoke
        ) { row in
            Button(NSLocalizedString("settings.connections.revoke", comment: ""), role: .destructive) {
                _Concurrency.Task { await model.revoke(row) }
            }
        } message: { row in
            Text(String(
                format: NSLocalizedString(
                    row.kind == .customAgent
                        ? "settings.connections.remove_agent_confirm"
                        : "settings.connections.revoke_confirm",
                    comment: ""
                ),
                row.name
            ))
        }
    }
}

// MARK: - One row

private struct ConnectionRow: View {
    let connection: Connection
    let isRevoking: Bool
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            HStack(alignment: .firstTextBaseline) {
                Text(connection.name.isEmpty ? connection.kind.localizedLabel : connection.name)
                    .font(Theme.Typography.body())
                    .lineLimit(1)
                Spacer()
                Text(connection.status.localizedLabel)
                    .font(Theme.Typography.caption2())
                    .foregroundStyle(connection.status == .active ? Color.green : Color.secondary)
            }

            Text(String(
                format: NSLocalizedString("settings.connections.acts_as", comment: ""),
                connection.actsAs ?? NSLocalizedString("settings.connections.acts_as_you", comment: "")
            ))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

            if !connection.scopes.isEmpty {
                Text(connection.scopes.joined(separator: " · "))
                    .font(Theme.Typography.caption2())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(ConnectionDates.summary(for: connection))
                .font(Theme.Typography.caption2())
                .foregroundStyle(.secondary)

            HStack {
                if connection.managedOnAgentsPage {
                    Text(NSLocalizedString("settings.connections.manage_in_agents", comment: ""))
                        .font(Theme.Typography.caption2())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRevoking {
                    ProgressView().controlSize(.small)
                } else if connection.revocable {
                    Button(role: .destructive, action: onRevoke) {
                        Label(NSLocalizedString("settings.connections.revoke", comment: ""), systemImage: "xmark.shield")
                            .font(Theme.Typography.caption1())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(connection.status == .active ? 1 : 0.7)
    }
}

// MARK: - Dates

/// The server sends ISO 8601 strings; the screen shows the user's short date, or "never".
enum ConnectionDates {
    private static let parsers: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [fractional, plain]
    }()

    static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        for parser in parsers {
            if let date = parser.date(from: iso) { return date }
        }
        return nil
    }

    static func display(_ iso: String?) -> String {
        guard let date = date(iso) else { return NSLocalizedString("settings.connections.never", comment: "") }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func summary(for connection: Connection) -> String {
        var parts = [
            String(format: NSLocalizedString("settings.connections.created", comment: ""), display(connection.createdAt)),
            String(format: NSLocalizedString("settings.connections.last_used", comment: ""), display(connection.lastUsedAt)),
        ]
        if let expiresAt = connection.expiresAt {
            parts.append(String(format: NSLocalizedString("settings.connections.expires", comment: ""), display(expiresAt)))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Minted transport credentials (shown once)

extension MintedOAuthClient: Identifiable {
    var id: String { clientId }
}

/// The one-time reveal of a transport's client credentials, the same shape as Custom Agent
/// registration's sheet so a secret is presented one way wherever it appears.
struct TransportCredentialsSheet: View {
    let minted: MintedOAuthClient
    let onDone: () -> Void
    @State private var copiedField: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(NSLocalizedString("settings.agents.webhook.credentials_warning", comment: ""), systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.body())
                        .foregroundColor(.orange)
                }
                Section {
                    CredentialCopyRow(
                        label: NSLocalizedString("settings.openclaw.credential.client_id", comment: ""),
                        value: minted.clientId, fieldId: "clientId", copiedField: $copiedField
                    )
                    CredentialCopyRow(
                        label: NSLocalizedString("settings.openclaw.credential.client_secret", comment: ""),
                        value: minted.clientSecret, fieldId: "clientSecret", copiedField: $copiedField, isSecret: true
                    )
                }
                Section {
                    Text(NSLocalizedString("settings.agents.webhook.credentials_needs_both", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundStyle(.secondary)
                }
            }
            .agentHubScreenChrome(NSLocalizedString("settings.agents.webhook.credentials_title", comment: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.done", comment: ""), action: onDone)
                }
            }
        }
        .agentHubNestedSheetSize()
    }
}

struct CredentialCopyRow: View {
    let label: String
    let value: String
    let fieldId: String
    @Binding var copiedField: String?
    var isSecret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.caption2())
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSecret ? Color.orange : Color.primary)
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
}
