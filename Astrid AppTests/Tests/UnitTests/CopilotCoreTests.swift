//  CopilotCoreTests.swift
//  The Agent Hub's Copilot connection and agent-mode writes go through astrid-core (AITD-620,
//  eighth slice): the commands it sends, the core's answer read back, and the hub model driving
//  them through its service seam.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests (`dispatch/tests/account.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

final class CopilotCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The commands

    func testConnectAndDisconnectAreTheCoresCopilotCommands_AITD620() throws {
        XCTAssertEqual(try json(CopilotCommands.connect())["kind"] as? String, "connectCopilot")
        XCTAssertEqual(try json(CopilotCommands.disconnect())["kind"] as? String, "disconnectCopilot")
    }

    /// The core's `setAgentMode` takes the mode mailbox and the mode as the server spells it.
    func testSettingAModeSendsTheMailboxAndTheLowercaseMode_AITD620() throws {
        let sent = try json(CopilotCommands.setMode(UpdateAgentModeRequest(agent: "openai", mode: .polling)))
        XCTAssertEqual(sent["kind"] as? String, "setAgentMode")
        XCTAssertEqual(sent["agent"] as? String, "openai")
        XCTAssertEqual(sent["mode"] as? String, "polling")
    }

    // MARK: The core's answer

    /// The core answers `connectCopilot` with `{ authorizeUrl }`, not the route's `{ url }`.
    func testTheCoresConnectAnswerReadsAsTheAuthorizationURL_AITD620() throws {
        let answer = try JSONDecoder().decode(CopilotAuthorizationResponse.self,
                                              from: Data(#"{"authorizeUrl":"https://github.com/login/oauth/authorize?x=1"}"#.utf8))
        XCTAssertEqual(answer.url, "https://github.com/login/oauth/authorize?x=1")
    }

    func testTheRoutesOwnSpellingStillReads_AITD620() throws {
        let answer = try JSONDecoder().decode(CopilotAuthorizationResponse.self,
                                              from: Data(#"{"url":"https://github.com/login"}"#.utf8))
        XCTAssertEqual(answer.url, "https://github.com/login")
    }

    // MARK: The model through its seam

    /// The core answers an empty URL when the server named none; that must not open a browser.
    @MainActor
    func testAnEmptyAuthorizationURLIsRefused_AITD620() async {
        let fake = FakeAgentHubService()
        fake.authorization = CopilotAuthorizationResponse(url: "")
        let model = AgentHubModel(service: fake)
        do {
            _ = try await model.copilotAuthorizationURL()
            XCTFail("an empty URL should throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badURL)
        }
    }

    /// The core's disconnect answers only "done"; a disconnect that did not throw is disconnected.
    @MainActor
    func testDisconnectingReadsAsDisconnected_AITD620() async {
        let fake = FakeAgentHubService()
        let model = AgentHubModel(service: fake)
        model.copilotConnected = true

        await model.disconnectCopilot()
        XCTAssertEqual(fake.disconnects, 1)
        XCTAssertFalse(model.copilotConnected)
        XCTAssertNil(model.setupErrorMessage)
    }

    @MainActor
    func testAFailedDisconnectStaysConnected_AITD620() async {
        let fake = FakeAgentHubService()
        fake.disconnectError = URLError(.notConnectedToInternet)
        let model = AgentHubModel(service: fake)
        model.copilotConnected = true

        await model.disconnectCopilot()
        XCTAssertTrue(model.copilotConnected)
        XCTAssertNotNil(model.setupErrorMessage)
    }
}
