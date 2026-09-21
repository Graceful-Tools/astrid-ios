//  OAuthClientEditorTests.swift
//  Creating and editing an OAuth client from the phone (AITD-419).
//
//  Until this task the Connections screen could only LIST and REVOKE: minting a client, or
//  changing its redirect URIs, meant the web developer console. These tests pin the rules that
//  move with the feature — the validation the web console enforces before it will POST, and the
//  grant-type pairing that keeps `refresh_token` from existing on its own.
//
//  Twin of astrid-web `components/oauth-app-manager.tsx` (`handleCreate`, `toggleGrantType`).
//  When one side's rule changes the other is wrong, so the mirroring is deliberate and named.

import XCTest
@testable import Astrid_App

final class OAuthClientEditorTests: XCTestCase {

    // MARK: - What a draft must carry before the server is asked

    func testADraftWithoutANameIsNotSendable() {
        var draft = OAuthClientDraft()
        draft.name = "   "
        draft.grantTypes = [.clientCredentials]
        XCTAssertEqual(draft.problem, .nameMissing)
        XCTAssertFalse(draft.isValid)
    }

    func testADraftWithNoGrantTypeIsNotSendable() {
        var draft = OAuthClientDraft()
        draft.name = "My script"
        draft.grantTypes = []
        XCTAssertEqual(draft.problem, .noGrantType)
    }

    /// The authorization-code grant sends the user to a browser and back, so the "back" has to
    /// be a URL the server already knows. Without one the client is registerable but unusable.
    func testAuthorizationCodeNeedsSomewhereToComeBackTo() {
        var draft = OAuthClientDraft()
        draft.name = "Browser app"
        draft.grantTypes = [.authorizationCode]
        draft.redirectURIText = ""
        XCTAssertEqual(draft.problem, .redirectURIRequired)

        draft.redirectURIText = "https://example.test/callback"
        XCTAssertNil(draft.problem)
    }

    func testClientCredentialsNeedsNoRedirectURI() {
        var draft = OAuthClientDraft()
        draft.name = "Server script"
        draft.grantTypes = [.clientCredentials]
        XCTAssertNil(draft.problem)
    }

    func testARedirectURIMustBeAnAbsoluteHTTPOrHTTPSURL() {
        var draft = OAuthClientDraft()
        draft.name = "Browser app"
        draft.grantTypes = [.authorizationCode]

        draft.redirectURIText = "myapp://callback"
        XCTAssertEqual(draft.problem, .invalidRedirectURI("myapp://callback"))

        draft.redirectURIText = "/just/a/path"
        XCTAssertEqual(draft.problem, .invalidRedirectURI("/just/a/path"))

        draft.redirectURIText = "http://localhost:3000/callback"
        XCTAssertNil(draft.problem, "http is allowed — a local dev callback is the common case")
    }

    /// The text view is one URI per line, and the blank lines a person leaves while typing are
    /// not errors.
    func testRedirectURIsAreOnePerLineWithBlanksAndPaddingIgnored() {
        var draft = OAuthClientDraft()
        draft.redirectURIText = "  https://a.test/cb  \n\n\thttps://b.test/cb\n"
        XCTAssertEqual(draft.redirectURIs, ["https://a.test/cb", "https://b.test/cb"])
    }

    /// The problem reported is the FIRST one a reader can act on, not a pile of them: a draft
    /// with no name and a bad URI says "name it" first, because that is the field at the top.
    func testTheProblemReportedIsTheFirstOneToFix() {
        var draft = OAuthClientDraft()
        draft.grantTypes = [.authorizationCode]
        draft.redirectURIText = "nonsense"
        XCTAssertEqual(draft.problem, .nameMissing)
    }

    // MARK: - Grant types travel in pairs

    /// `refresh_token` on its own is meaningless: refresh tokens are issued by the
    /// authorization-code flow. astrid-web's `toggleGrantType` pairs them in both directions and
    /// so does this, or a client minted on the phone would differ from one minted on the web.
    func testTurningOnRefreshTokenAlsoTurnsOnAuthorizationCode() {
        let next = OAuthClientDraft.toggling(.refreshToken, in: [.clientCredentials])
        XCTAssertEqual(next, [.clientCredentials, .authorizationCode, .refreshToken])
    }

    func testTurningOnAuthorizationCodeAlsoTurnsOnRefreshToken() {
        let next = OAuthClientDraft.toggling(.authorizationCode, in: [.clientCredentials])
        XCTAssertEqual(next, [.clientCredentials, .authorizationCode, .refreshToken])
    }

    func testTurningOffAuthorizationCodeTakesRefreshTokenWithIt() {
        let next = OAuthClientDraft.toggling(.authorizationCode, in: [.clientCredentials, .authorizationCode, .refreshToken])
        XCTAssertEqual(next, [.clientCredentials])
    }

    /// Every grant off would be a client that cannot obtain a token by any route, so the last
    /// one cannot be turned off — the same refusal astrid-web makes by returning the previous set.
    func testTheLastGrantTypeCannotBeTurnedOff() {
        let next = OAuthClientDraft.toggling(.clientCredentials, in: [.clientCredentials])
        XCTAssertEqual(next, [.clientCredentials], "turning off the only grant would leave a client that can never authenticate")
    }

    // MARK: - The body that goes on the wire

    func testTheCreateRequestCarriesExactlyWhatTheServerReads() throws {
        var draft = OAuthClientDraft()
        draft.name = "  My script  "
        draft.descriptionText = "  Nightly export  "
        draft.scopes = ["tasks:read", "lists:read"]
        draft.grantTypes = [.clientCredentials]
        draft.redirectURIText = ""

        let request = draft.createRequest()
        XCTAssertEqual(request.name, "My script", "the name is trimmed — trailing spaces are a typo, not a name")
        XCTAssertEqual(request.description, "Nightly export")
        XCTAssertEqual(request.scopes.sorted(), ["lists:read", "tasks:read"])
        XCTAssertEqual(request.grantTypes, ["client_credentials"])
        XCTAssertNil(request.redirectUris, "no URIs means the key is absent, not an empty array")
    }

    func testAnEmptyDescriptionIsSentAsNullRatherThanAnEmptyString() {
        var draft = OAuthClientDraft()
        draft.name = "My script"
        draft.descriptionText = "   "
        XCTAssertNil(draft.createRequest().description)
    }

    /// Grant types go out in a stable order so two identical drafts produce identical bodies —
    /// a `Set` iterated raw would not.
    func testGrantTypesAreSentInAStableOrder() {
        var draft = OAuthClientDraft()
        draft.name = "Browser app"
        draft.grantTypes = [.refreshToken, .authorizationCode, .clientCredentials]
        draft.redirectURIText = "https://example.test/cb"
        XCTAssertEqual(draft.createRequest().grantTypes, ["client_credentials", "authorization_code", "refresh_token"])
    }

    // MARK: - The scope catalog mirrors the server's

    /// The wildcard grants the whole account and the server refuses to register it
    /// (`isRegisterableScope`). Offering it as a toggle would be a checkbox that always fails.
    func testTheScopePickerNeverOffersTheWildcard() {
        XCTAssertFalse(OAuthScopeCatalog.registerable.contains("*"))
        XCTAssertTrue(OAuthScopeCatalog.registerable.contains("tasks:read"))
        XCTAssertTrue(OAuthScopeCatalog.registerable.contains("chat:write"))
        XCTAssertTrue(OAuthScopeCatalog.registerable.contains("lists:manage_members"))
    }

    func testTheScopeCatalogHasNoDuplicates() {
        XCTAssertEqual(Set(OAuthScopeCatalog.registerable).count, OAuthScopeCatalog.registerable.count)
    }

    // MARK: - Decoding a client to edit

    func testAClientDecodesFromTheServersShapeAndSurvivesMissingFields() throws {
        let json = """
        {"client":{"id":"row-1","clientId":"astrid_client_abc","name":"My script","description":null,
         "redirectUris":["https://example.test/cb"],"grantTypes":["client_credentials"],
         "scopes":["tasks:read"],"scopeGroup":null,"isActive":true,
         "createdAt":"2026-09-01T10:00:00.000Z","updatedAt":"2026-09-01T10:00:00.000Z","lastUsedAt":null},
         "meta":{"apiVersion":"v1"}}
        """
        let client = try JSONDecoder().decode(OAuthClientResponse.self, from: Data(json.utf8)).client
        XCTAssertEqual(client.clientId, "astrid_client_abc")
        XCTAssertEqual(client.name, "My script")
        XCTAssertNil(client.description)
        XCTAssertEqual(client.redirectUris, ["https://example.test/cb"])
        XCTAssertEqual(client.grantTypes, ["client_credentials"])
        XCTAssertTrue(client.isActive)

        let sparse = """
        {"client":{"clientId":"astrid_client_xyz"},"meta":{"apiVersion":"v1"}}
        """
        let bare = try JSONDecoder().decode(OAuthClientResponse.self, from: Data(sparse.utf8)).client
        XCTAssertEqual(bare.clientId, "astrid_client_xyz")
        XCTAssertEqual(bare.redirectUris, [], "a field the server omitted is empty, not a decode failure")
        XCTAssertTrue(bare.isActive, "absent isActive reads as active — the list only shows live clients")
    }

    /// A client loaded for editing fills the draft, so the authorization-code rule applies to an
    /// EDIT too: you cannot empty the redirect URIs of a client that needs one.
    func testLoadingAClientIntoADraftKeepsItsGrantTypesInForce() throws {
        let client = OAuthClientSummary(
            clientId: "astrid_client_abc", name: "Browser app", description: nil,
            redirectUris: ["https://example.test/cb"],
            grantTypes: ["authorization_code", "refresh_token"], scopes: ["tasks:read"], isActive: true
        )
        var draft = OAuthClientDraft(client)
        XCTAssertEqual(draft.name, "Browser app")
        XCTAssertEqual(draft.grantTypes, [.authorizationCode, .refreshToken])
        XCTAssertEqual(draft.redirectURIText, "https://example.test/cb")
        XCTAssertNil(draft.problem)

        draft.redirectURIText = ""
        XCTAssertEqual(draft.problem, .redirectURIRequired,
                       "clearing the callback of an authorization-code client must not be savable")
    }

    /// A grant type this build has never heard of must not vanish on a round trip: the draft
    /// keeps it and sends it back, so editing the redirect URIs of a client the server minted
    /// with a newer grant does not quietly narrow it.
    func testAnUnknownGrantTypeSurvivesAnEdit() throws {
        let client = OAuthClientSummary(
            clientId: "astrid_client_abc", name: "Future app", description: nil,
            redirectUris: [], grantTypes: ["client_credentials", "device_code"], scopes: [], isActive: true
        )
        let draft = OAuthClientDraft(client)
        XCTAssertEqual(draft.grantTypes, [.clientCredentials])
        XCTAssertEqual(draft.unrecognizedGrantTypes, ["device_code"])
        XCTAssertEqual(draft.createRequest().grantTypes, ["client_credentials", "device_code"])
    }

    // MARK: - The round trip

    @MainActor
    func testCreatingHoldsTheSecretOpenRatherThanClosingTheSheet() async {
        let service = FakeConnectionsService()
        let model = OAuthClientEditorModel(mode: .create, service: service)
        model.draft.name = "My script"
        model.draft.scopes = ["tasks:read"]

        let shouldClose = await model.save()
        XCTAssertFalse(shouldClose, "closing on top of the secret would lose the only copy there will ever be")
        XCTAssertEqual(model.minted?.clientSecret, "shh")
        XCTAssertEqual(service.createdClients.count, 1)
        XCTAssertEqual(service.createdClients.first?.name, "My script")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testAnInvalidDraftNeverReachesTheServer() async {
        let service = FakeConnectionsService()
        let model = OAuthClientEditorModel(mode: .create, service: service)
        model.draft.name = ""

        let shouldClose = await model.save()
        XCTAssertFalse(shouldClose)
        XCTAssertTrue(service.createdClients.isEmpty, "a draft the client can reject is one the server never sees")
        XCTAssertEqual(model.errorMessage, OAuthClientDraft.Problem.nameMissing.localizedMessage)
    }

    @MainActor
    func testEditingLoadsTheClientAndWritesBackOnlyItsRedirectURIs() async {
        let service = FakeConnectionsService()
        service.clients["astrid_client_abc"] = OAuthClientSummary(
            clientId: "astrid_client_abc", name: "Browser app", description: "Nightly",
            redirectUris: ["https://old.test/cb"], grantTypes: ["authorization_code", "refresh_token"],
            scopes: ["tasks:read"], isActive: true
        )
        let model = OAuthClientEditorModel(mode: .edit(clientId: "astrid_client_abc"), service: service)

        await model.load()
        XCTAssertEqual(model.draft.name, "Browser app")
        XCTAssertEqual(model.draft.redirectURIText, "https://old.test/cb")

        model.draft.redirectURIText = "https://new.test/cb\nhttps://other.test/cb"
        let shouldClose = await model.save()

        XCTAssertTrue(shouldClose, "an edit has nothing to show afterwards, so the sheet closes")
        XCTAssertEqual(service.updatedClients.count, 1)
        XCTAssertEqual(service.updatedClients.first?.clientId, "astrid_client_abc")
        XCTAssertEqual(service.updatedClients.first?.body.redirectUris, ["https://new.test/cb", "https://other.test/cb"])
        XCTAssertNil(model.minted, "an edit mints nothing — there is no new secret to reveal")
    }

    /// Registration is session-only server-side. iOS sends the account session cookie so it
    /// normally succeeds, but a 403 must read as "do this on the web", not as a bare error — the
    /// same handling the revoke path already has.
    @MainActor
    func testASessionOnlyRefusalPointsAtTheWebRatherThanFailingBlankly() async {
        let service = FakeConnectionsService()
        service.createClientError = AstridAPIError.httpError(statusCode: 403, message: "{\"error\":\"Client registration requires an interactive session\"}")
        let model = OAuthClientEditorModel(mode: .create, service: service)
        model.draft.name = "My script"

        _ = await model.save()
        XCTAssertTrue(model.requiresWebSession)
        XCTAssertEqual(model.errorMessage, "Client registration requires an interactive session")
        XCTAssertNil(model.minted)
    }

    // MARK: - Which rows offer an Edit button

    func testOnlyAnOAuthClientThisScreenOwnsIsEditableHere() {
        let editable = Connection(id: "c1", kind: .oauthClient, name: "My script",
                                  manageIn: "connections", detail: ConnectionDetail(clientId: "astrid_client_abc"))
        XCTAssertEqual(ConnectionsScreen.editableClientId(editable), "astrid_client_abc")

        let agentOwned = Connection(id: "c2", kind: .oauthClient, name: "Webhook transport",
                                    manageIn: "agents", detail: ConnectionDetail(clientId: "astrid_client_xyz"))
        XCTAssertNil(ConnectionsScreen.editableClientId(agentOwned), "the Agent Hub owns this one; two owners disagree")

        let approvedApp = Connection(id: "c3", kind: .authorizedApp, name: "Claude Code",
                                     manageIn: "connections", detail: ConnectionDetail(activeTokens: 2))
        XCTAssertNil(ConnectionsScreen.editableClientId(approvedApp), "an approved app has no redirect URIs of ours to change")

        let noClientId = Connection(id: "c4", kind: .oauthClient, name: "Mystery", manageIn: "connections", detail: nil)
        XCTAssertNil(ConnectionsScreen.editableClientId(noClientId), "no client id is a row this build cannot address")
    }

    // MARK: - The endpoint the edit writes to

    func testTheClientPathNamesTheClientBeingEdited() {
        XCTAssertEqual(
            AstridAPIClient.oauthClientPath("astrid_client_abc"),
            "/api/v1/oauth/clients/astrid_client_abc"
        )
    }
}
