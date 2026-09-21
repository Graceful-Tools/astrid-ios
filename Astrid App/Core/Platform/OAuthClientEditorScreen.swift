//  OAuthClientEditorScreen.swift
//  Making a new API connection, and changing one that exists, without leaving the app (AITD-419).
//
//  Written once for iOS and Mac like the rest of the Connections screen. Native twin of
//  astrid-web `components/oauth-app-manager.tsx` (create) and `components/oauth-client-edit-dialog.tsx`
//  (edit), and deliberately offers the same narrow edit the web dialog does — redirect URIs, with
//  name and description shown but fixed — so a connection means the same thing on both.
//
//  Scopes are shown as their raw identifiers (`tasks:read`) rather than translated prose. That is
//  how the connection rows already display them, and a scope is an API token the server matches
//  literally — inventing twelve translations of each would make the list prettier and the thing
//  you are granting harder to check against the docs.

import SwiftUI

struct OAuthClientEditorScreen: View {
    @StateObject private var model: OAuthClientEditorModel
    /// Called when the client list behind the sheet needs to catch up.
    let onFinished: () -> Void
    let onCancel: () -> Void

    init(mode: OAuthClientEditorModel.Mode, onFinished: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _model = StateObject(wrappedValue: OAuthClientEditorModel(mode: mode))
        self.onFinished = onFinished
        self.onCancel = onCancel
    }

    private var title: String {
        NSLocalizedString(model.isEditing ? "settings.connections.edit_title" : "settings.connections.new_title", comment: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.isLoading {
                    Section {
                        HStack { ProgressView(); Text(NSLocalizedString("settings.agents.loading", comment: "")) }
                    }
                } else {
                    identitySection
                    grantTypesSection
                    redirectURIsSection
                    scopesSection
                }

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
            }
            .agentHubScreenChrome(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: ""), action: onCancel)
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(NSLocalizedString(model.isEditing ? "actions.save" : "settings.connections.create", comment: "")) {
                            _Concurrency.Task {
                                if await model.save() { onFinished() }
                            }
                        }
                        .disabled(!model.draft.isValid || model.isLoading)
                    }
                }
            }
            .task { await model.load() }
        }
        .agentHubNestedSheetSize()
        .sheet(item: $model.minted) { minted in
            // The secret exists in exactly one place until this sheet is dismissed.
            TransportCredentialsSheet(minted: minted) {
                model.minted = nil
                onFinished()
            }
        }
    }

    // MARK: - Name and description

    @ViewBuilder
    private var identitySection: some View {
        Section {
            if model.isEditing {
                Text(model.draft.name)
                    .foregroundStyle(.secondary)
            } else {
                plainField(NSLocalizedString("settings.connections.field.name_placeholder", comment: ""),
                           text: $model.draft.name)
            }
        } header: {
            Text(NSLocalizedString("settings.connections.field.name", comment: ""))
        } footer: {
            if model.isEditing {
                Text(NSLocalizedString("settings.connections.name_fixed", comment: ""))
                    .font(Theme.Typography.caption2())
            }
        }

        Section(NSLocalizedString("settings.connections.field.description", comment: "")) {
            if model.isEditing {
                Text(model.draft.descriptionText.isEmpty
                     ? NSLocalizedString("settings.connections.field.description_none", comment: "")
                     : model.draft.descriptionText)
                    .foregroundStyle(.secondary)
            } else {
                plainField(NSLocalizedString("settings.connections.field.description_placeholder", comment: ""),
                           text: $model.draft.descriptionText)
            }
        }
    }

    // MARK: - Grant types

    private var grantTypesSection: some View {
        Section(NSLocalizedString("settings.connections.field.grant_types", comment: "")) {
            ForEach(OAuthGrantType.displayOrder, id: \.self) { grant in
                Toggle(isOn: Binding(
                    get: { model.draft.grantTypes.contains(grant) },
                    // The pairing rule lives in the draft, not here: a toggle that quietly turns
                    // on a second one is a rule, and rules belong where a test can reach them.
                    set: { _ in model.draft.grantTypes = OAuthClientDraft.toggling(grant, in: model.draft.grantTypes) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(grant.localizedLabel).font(Theme.Typography.body())
                        Text(grant.localizedHint)
                            .font(Theme.Typography.caption2())
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isEditing)
            }
        }
    }

    // MARK: - Redirect URIs

    private var redirectURIsSection: some View {
        Section(
            header: Text(NSLocalizedString("settings.connections.field.redirect_uris", comment: "")),
            footer: Text(NSLocalizedString("settings.connections.field.redirect_uris_hint", comment: ""))
                .font(Theme.Typography.caption2())
        ) {
            TextEditor(text: $model.draft.redirectURIText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 72)
                #if !os(macOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

            if let problem = model.draft.problem, isRedirectProblem(problem) {
                Text(problem.localizedMessage)
                    .font(Theme.Typography.caption2())
                    .foregroundStyle(.red)
            }
        }
    }

    /// Only the redirect problems belong under the redirect field; a missing name reported here
    /// would point at the wrong box.
    private func isRedirectProblem(_ problem: OAuthClientDraft.Problem) -> Bool {
        switch problem {
        case .redirectURIRequired, .invalidRedirectURI: return true
        case .nameMissing, .noGrantType: return false
        }
    }

    // MARK: - Scopes

    private var scopesSection: some View {
        Section(
            header: Text(NSLocalizedString("settings.connections.field.scopes", comment: "")),
            footer: Text(model.draft.scopes.isEmpty
                         ? NSLocalizedString("settings.connections.scopes_none", comment: "")
                         : NSLocalizedString("settings.connections.scopes_hint", comment: ""))
                .font(Theme.Typography.caption2())
        ) {
            if model.isEditing {
                // The PUT would accept a scope list, but the web dialog does not offer one and
                // widening a live connection's reach is not something to do by accident.
                Text(model.draft.scopes.isEmpty
                     ? NSLocalizedString("settings.connections.scopes_none", comment: "")
                     : model.draft.scopes.sorted().joined(separator: " · "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(OAuthScopeCatalog.registerable, id: \.self) { scope in
                    Toggle(isOn: Binding(
                        get: { model.draft.scopes.contains(scope) },
                        set: { isOn in
                            if isOn { model.draft.scopes.insert(scope) } else { model.draft.scopes.remove(scope) }
                        }
                    )) {
                        Text(scope).font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - Fields

    @ViewBuilder
    private func plainField(_ placeholder: String, text: Binding<String>) -> some View {
        let field = TextField(placeholder, text: text)
        #if os(macOS)
        field.textFieldStyle(.roundedBorder)
        #else
        field.autocorrectionDisabled()
        #endif
    }
}
