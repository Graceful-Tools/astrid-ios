//  AgentCredentialsCoreTests.swift
//  The Agent Hub's AI keys and its two reads — the agent modes and the Copilot status — go
//  through astrid-core (AITD-620, tenth slice, on the commands AWTD-1610 added at core 084c2c0):
//  the commands it sends, the core's answers read back, and the hub model driving them.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests (`dispatch/tests/account.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

final class AgentCredentialsCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The commands

    func testTheKeyReadIsTheCoresStandaloneCredentialsCommand_AITD620() throws {
        XCTAssertEqual(try json(AgentCredentialCommands.list())["kind"] as? String, "agentCredentials")
    }

    /// The core names the key `key`, not the route's `apiKey`, and renames it on the wire itself.
    func testSavingAKeySendsTheServiceAndTheKey_AITD620() throws {
        let sent = try json(AgentCredentialCommands.save(serviceId: "openai", key: "sk-x"))
        XCTAssertEqual(sent["kind"] as? String, "saveAgentCredential")
        XCTAssertEqual(sent["serviceId"] as? String, "openai")
        XCTAssertEqual(sent["key"] as? String, "sk-x")
        XCTAssertNil(sent["apiKey"])
    }

    func testTestingAndDeletingNameOnlyTheService_AITD620() throws {
        let test = try json(AgentCredentialCommands.test(serviceId: "claude"))
        XCTAssertEqual(test["kind"] as? String, "testAgentCredential")
        XCTAssertEqual(test["serviceId"] as? String, "claude")

        let delete = try json(AgentCredentialCommands.delete(serviceId: "gemini"))
        XCTAssertEqual(delete["kind"] as? String, "deleteAgentCredential")
        XCTAssertEqual(delete["serviceId"] as? String, "gemini")
    }

    func testTheHubReadsAreTheCoresStandaloneCommands_AITD620() throws {
        XCTAssertEqual(try json(CopilotCommands.modes())["kind"] as? String, "agentModes")
        XCTAssertEqual(try json(CopilotCommands.status())["kind"] as? String, "copilotStatus")
    }

    // MARK: The core's answers

    /// The core's `testAgentCredential` answers `{ works, error }`; the error is the server's
    /// reason, which the key rows show (the reason AWTD-1610 widened it).
    func testTheCoresKeyTestAnswerKeepsTheServersReason_AITD620() throws {
        let failed = try JSONDecoder().decode(TestAPIKeyResponse.self,
                                              from: Data(#"{"works":false,"error":"Invalid x-api-key"}"#.utf8))
        XCTAssertFalse(failed.success)
        XCTAssertEqual(failed.error, "Invalid x-api-key")

        let works = try JSONDecoder().decode(TestAPIKeyResponse.self, from: Data(#"{"works":true,"error":null}"#.utf8))
        XCTAssertTrue(works.success)
        XCTAssertNil(works.error)
    }

    func testTheCoresCredentialsAnswerReadsAsTheKeyStatuses_AITD620() throws {
        let answer = try JSONDecoder().decode(AIAPIKeysResponse.self, from: Data(#"""
        {"keys":{"openai":{"hasKey":true,"keyPreview":"sk-...abcd","isValid":true,"lastTested":"2026-11-12T10:00:00Z","error":null}}}
        """#.utf8))
        XCTAssertEqual(answer.keys["openai"]?.hasKey, true)
        XCTAssertEqual(answer.keys["openai"]?.keyPreview, "sk-...abcd")
        XCTAssertNil(answer.keys["claude"])
    }

    /// The core's `agentModes` answers `{ agents, modes }` with no `meta`.
    func testTheCoresModesAnswerReadsWithoutMeta_AITD620() throws {
        let answer = try JSONDecoder().decode(AgentModesResponse.self, from: Data(#"""
        {"agents":[{"mailbox":"openai","email":"openai@astrid.cc","mode":"polling","locked":false}],"modes":{"openai":"polling"}}
        """#.utf8))
        XCTAssertEqual(answer.modes["openai"], .polling)
        XCTAssertEqual(answer.agents.first?.mailbox, "openai")
        XCTAssertNil(answer.meta)
    }

    // MARK: The model through its seam

    /// Saving answers only "done", so the hub re-reads the statuses to show the new preview.
    @MainActor
    func testSavingAKeyRereadsTheStatuses_AITD620() async {
        let fake = FakeAgentHubService()
        fake.keysResult = .success(AIAPIKeysResponse(keys: [
            "openai": AIAPIKeyStatus(hasKey: true, keyPreview: "sk-...abcd", isValid: nil, lastTested: nil, error: nil),
        ]))
        let model = AgentHubModel(service: fake)

        await model.saveKey("  sk-abcd  ", for: "openai")
        XCTAssertEqual(fake.savedKeys.first?.serviceId, "openai")
        XCTAssertEqual(fake.savedKeys.first?.key, "sk-abcd")
        XCTAssertEqual(fake.keysReads, 1)
        XCTAssertEqual(model.keyStatuses["openai"]?.keyPreview, "sk-...abcd")
        XCTAssertNil(model.actionErrorMessage)
    }

    /// A failed test shows the server's reason on the row and as the hub's message.
    @MainActor
    func testAFailedKeyTestShowsTheServersReason_AITD620() async {
        let fake = FakeAgentHubService()
        fake.testResult = TestAPIKeyResponse(success: false, error: "Invalid x-api-key")
        let model = AgentHubModel(service: fake)
        model.keyStatuses["claude"] = AIAPIKeyStatus(hasKey: true, keyPreview: "sk-ant-...", isValid: nil, lastTested: nil, error: nil)

        let result = await model.testKey(for: "claude")
        XCTAssertEqual(result?.success, false)
        XCTAssertEqual(model.keyStatuses["claude"]?.isValid, false)
        XCTAssertEqual(model.keyStatuses["claude"]?.error, "Invalid x-api-key")
        XCTAssertEqual(model.actionErrorMessage, "Invalid x-api-key")
    }

    /// Deleting answers only "done"; a delete that did not throw removes the row's status.
    @MainActor
    func testDeletingAKeyRemovesItsStatus_AITD620() async {
        let fake = FakeAgentHubService()
        let model = AgentHubModel(service: fake)
        model.keyStatuses["gemini"] = AIAPIKeyStatus(hasKey: true, keyPreview: "AIza...", isValid: true, lastTested: nil, error: nil)

        await model.deleteKey(for: "gemini")
        XCTAssertEqual(fake.deletedKeys, ["gemini"])
        XCTAssertNil(model.keyStatuses["gemini"])
    }
}
