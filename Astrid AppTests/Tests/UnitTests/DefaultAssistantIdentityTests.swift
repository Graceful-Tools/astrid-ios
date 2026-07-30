import XCTest
@testable import Astrid_App

/// Whitelabel Phase 4 (task 97208a72).
///
/// The agent-email domain is server-side configuration — agent identities are
/// `<mailbox>@<BRAND_AGENT_EMAIL_DOMAIN>`, so `astrid@astrid.cc` is only what Astrid's
/// own deployment happens to use. DefaultAgentPickerView filtered the assistant out of
/// its model list by matching that literal address, which meant a rebranded server
/// would list the assistant as a model that powers itself.
///
/// The available-agents response already carries `service: "astrid"` for that row, so
/// clients identify it by service and need no API change.
final class DefaultAssistantIdentityTests: XCTestCase {

    private func agent(email: String, service: String) -> AvailableAgent {
        AvailableAgent(id: "u-\(service)", name: service, email: email, image: nil, service: service)
    }

    func testAssistantIsIdentifiedByServiceNotEmail() {
        let assistant = agent(email: "astrid@astrid.cc", service: "astrid")

        XCTAssertTrue(assistant.isDefaultAssistant)
    }

    func testAssistantIsRecognisedOnARebrandedDomain() {
        // The whole point: same row, different deployment domain.
        let assistant = agent(email: "astrid@acme.example", service: "astrid")

        XCTAssertTrue(assistant.isDefaultAssistant)
    }

    func testProviderAgentsAreNotTheAssistant() {
        for service in ["claude", "openai", "gemini", "copilot", "openclaw"] {
            let provider = agent(email: "\(service)@acme.example", service: service)
            XCTAssertFalse(provider.isDefaultAssistant, "\(service) must not read as the assistant")
        }
    }

    /// Mirrors DefaultAgentPickerView.modelOptions: the assistant is excluded from the
    /// list of models that can power it, on any domain.
    func testModelOptionsExcludeTheAssistantOnAnyDomain() {
        let agents = [
            agent(email: "astrid@acme.example", service: "astrid"),
            agent(email: "claude@acme.example", service: "claude"),
            agent(email: "gemini@acme.example", service: "gemini"),
        ]

        let modelOptions = agents.filter { !$0.isDefaultAssistant }

        XCTAssertEqual(modelOptions.count, 2)
        XCTAssertFalse(modelOptions.contains { $0.service == "astrid" })
    }

    func testAssistantStillCountsAsBuiltIn() {
        let assistant = agent(email: "astrid@acme.example", service: "astrid")

        XCTAssertTrue(assistant.isBuiltIn)
    }
}
