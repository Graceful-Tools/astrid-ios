//  CustomAgentsCoreTests.swift
//  The Custom Agents section goes through astrid-core (AITD-620, fourth slice): the commands it
//  sends, and the section's model driving them through its service seam.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests (`dispatch/tests/account.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

final class CustomAgentsCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The commands

    func testListingIsTheCoresCustomAgentsCommand_AITD620() throws {
        XCTAssertEqual(try json(CustomAgentCommands.list())["kind"] as? String, "customAgents")
    }

    /// The core calls the name `name` and renames it to the wire's `agentName` itself.
    func testRegisteringSendsTheNameAndTheChosenLists_AITD620() throws {
        let sent = try json(CustomAgentCommands.register(name: "my-bot", listIds: ["l1", "l2"]))
        XCTAssertEqual(sent["kind"] as? String, "registerCustomAgent")
        XCTAssertEqual(sent["name"] as? String, "my-bot")
        XCTAssertEqual(sent["listIds"] as? [String], ["l1", "l2"])
        XCTAssertNil(sent["agentName"], "the core would ignore it and refuse the missing name")
    }

    /// No lists chosen leaves the field absent, so the server's own default applies, as before.
    func testRegisteringWithNoListsLeavesTheFieldAbsent_AITD620() throws {
        let sent = try json(CustomAgentCommands.register(name: "my-bot", listIds: nil))
        XCTAssertFalse(sent.keys.contains("listIds"))
    }

    func testDeletingNamesTheAgent_AITD620() throws {
        let sent = try json(CustomAgentCommands.delete(id: "agent-7"))
        XCTAssertEqual(sent["kind"] as? String, "deleteCustomAgent")
        XCTAssertEqual(sent["agentId"] as? String, "agent-7")
    }

    func testAPhotoIsTheCoresSetCustomAgentPhotoCommand_AITD620() throws {
        let sent = try json(CustomAgentCommands.setPhoto(id: "agent-7", image: "https://img.test/a.jpg"))
        XCTAssertEqual(sent["kind"] as? String, "setCustomAgentPhoto")
        XCTAssertEqual(sent["agentId"] as? String, "agent-7")
        XCTAssertEqual(sent["image"] as? String, "https://img.test/a.jpg")
    }

    // MARK: The model through its seam

    @MainActor
    func testRegisteringKeepsTheOneTimeCredentialsAndRereadsTheList_AITD620() async {
        let fake = FakeCustomAgentsService()
        let model = CustomAgentsModel(service: fake)
        fake.agents = [Self.agent("a1", "my-bot")]

        let ok = await model.register(name: " My-Bot ", listIds: ["l1"])
        XCTAssertTrue(ok)
        XCTAssertEqual(fake.registered.first?.name, "my-bot")
        XCTAssertEqual(fake.registered.first?.listIds, ["l1"])
        XCTAssertEqual(model.registrationResult?.oauth.clientSecret, "secret-once")
        XCTAssertEqual(model.agents.map(\.id), ["a1"])
    }

    @MainActor
    func testDeletingRemovesTheAgent_AITD620() async {
        let fake = FakeCustomAgentsService()
        fake.agents = [Self.agent("a1", "one"), Self.agent("a2", "two")]
        let model = CustomAgentsModel(service: fake)
        await model.load()

        await model.delete(model.agents[0])
        XCTAssertEqual(fake.deleted, ["a1"])
        XCTAssertEqual(model.agents.map(\.id), ["a2"])
        XCTAssertNil(model.errorMessage)
    }

    static func agent(_ id: String, _ name: String) -> CustomAgent {
        CustomAgent(id: id, email: "\(name).oc@astrid.cc", name: name, image: nil, agentName: name,
                    status: "idle", registeredAt: "2026-11-12T00:00:00Z", lastActiveAt: nil,
                    oauthClientId: nil)
    }
}

private final class FakeCustomAgentsService: CustomAgentsServicing {
    var agents: [CustomAgent] = []
    private(set) var registered: [(name: String, listIds: [String]?)] = []
    private(set) var deleted: [String] = []

    func getCustomAgents() async throws -> [CustomAgent] { agents }

    func registerCustomAgent(name: String, listIds: [String]?) async throws -> CustomAgentRegistrationResult {
        registered.append((name, listIds))
        return CustomAgentRegistrationResult(
            agent: CustomAgentRegistrationAgent(id: "a1", email: "my-bot.oc@astrid.cc", name: name,
                                                aiAgentType: "openclaw_worker"),
            oauth: CustomAgentRegistrationOAuth(clientId: "c1", clientSecret: "secret-once", scopes: ["read"]),
            config: CustomAgentRegistrationConfig(sseEndpoint: "/sse", apiBase: "/api/v1", tokenEndpoint: "/token")
        )
    }

    func updateCustomAgent(id: String, image: String?) async throws -> CustomAgentUpdateResponse {
        CustomAgentUpdateResponse(success: true, image: image)
    }

    func deleteCustomAgent(id: String) async throws { deleted.append(id) }

    func createCopilotCloudAgentToken() async throws -> MCPUserTokenResponse {
        MCPUserTokenResponse(token: "t", expiresAt: nil)
    }
}
