//  AgentServiceIconTests.swift
//  The assistant-model picker draws each provider's real brand mark (AITD-450).
//
//  The picker loaded the server's icon URL with `.svg` rewritten to `.png`, and
//  `/images/ai-agents/copilot.png` does not exist (404, measured 2026-10-02). The fallback was
//  `serviceImageAsset`, which had no Copilot case — so GitHub Copilot showed a generic sparkles
//  glyph while the bundled `ai-copilot` asset, the actual Copilot mark, sat unused.

import XCTest
@testable import Astrid_App

final class AgentServiceIconTests: XCTestCase {

    private func agent(service: String) -> AvailableAgent {
        AvailableAgent(id: "id-\(service)", name: service, email: "\(service)@astrid.cc",
                       image: "/images/ai-agents/\(service).svg", service: service)
    }

    /// AITD-450: Copilot has a bundled brand mark, so it must be the one drawn.
    func testCopilotUsesItsBundledBrandMark() {
        XCTAssertEqual(agent(service: "copilot").serviceImageAsset, "ai-copilot")
    }

    /// Every server-run agent the hub draws with a bundled mark gets the SAME mark in the
    /// assistant-model picker — the two screens disagreed for Copilot.
    func testThePickerMatchesTheAgentHubForEveryServerRunAgent() {
        for row in AgentRuntimeRow.all where !row.isHarnessOnly {
            XCTAssertEqual(agent(service: row.service).serviceImageAsset, row.imageAsset,
                           "\(row.label) is drawn differently in the hub and the model picker")
        }
    }

    /// A known provider is drawn from the bundle, never from the network: the network copy is
    /// what 404'd. Only an agent with no bundled mark (a custom OpenClaw agent) goes remote.
    func testABundledMarkWinsOverTheServerImage() {
        XCTAssertEqual(agent(service: "copilot").avatarSource, .bundled("ai-copilot"))
        guard case .remote = agent(service: "custom-thing").avatarSource else {
            return XCTFail("an agent with no bundled mark should use its server image")
        }
    }
}
