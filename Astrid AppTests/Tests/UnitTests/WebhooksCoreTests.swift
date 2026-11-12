//  WebhooksCoreTests.swift
//  The agents page's webhook transport goes through astrid-core (AITD-620, second slice): the
//  commands it sends, and the editor model driving them through its service seam.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests (`dispatch/tests/account.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

final class WebhooksCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The commands

    func testReadingTheSettingsIsTheCoresWebhookSettingsCommand_AITD620() throws {
        XCTAssertEqual(try json(WebhookCommands.settings())["kind"] as? String, "webhookSettings")
    }

    /// The core's `saveWebhook` names the URL `url`, not the wire's `webhookUrl`, and sends the
    /// rest under the web editor's names itself.
    func testASaveSendsTheEditorsFiveFieldsInTheCoresShape_AITD620() throws {
        let sent = try json(WebhookCommands.save(UpdateWebhookSettingsRequest(
            webhookUrl: "https://hooks.test/astrid", enabled: false, regenerateSecret: true,
            events: ["task.assigned"], agents: ["claude", "codex"])))
        XCTAssertEqual(sent["kind"] as? String, "saveWebhook")
        XCTAssertEqual(sent["url"] as? String, "https://hooks.test/astrid")
        XCTAssertEqual(sent["enabled"] as? Bool, false)
        XCTAssertEqual(sent["regenerateSecret"] as? Bool, true)
        XCTAssertEqual(sent["events"] as? [String], ["task.assigned"])
        XCTAssertEqual(sent["agents"] as? [String], ["claude", "codex"])
        XCTAssertNil(sent["webhookUrl"], "the core would ignore it and refuse the missing url")
    }

    func testDeleteAndTestAreTheCoresCommands_AITD620() throws {
        XCTAssertEqual(try json(WebhookCommands.delete())["kind"] as? String, "deleteWebhook")
        XCTAssertEqual(try json(WebhookCommands.test())["kind"] as? String, "testWebhook")
    }

    // MARK: The model through its seam

    @MainActor
    func testDeletingClearsTheEditor_AITD620() async {
        let fake = FakeWebhookService()
        fake.settings = WebhookSettings(configured: true, webhookUrl: "https://hooks.test/a")
        let model = WebhookSettingsModel(service: fake)
        await model.load()
        XCTAssertEqual(model.webhookUrl, "https://hooks.test/a")

        await model.delete()
        XCTAssertEqual(fake.deletes, 1)
        XCTAssertEqual(model.settings, .unconfigured)
        XCTAssertEqual(model.webhookUrl, "")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testASaveShowsTheSecretOnceAndRereadsTheSettings_AITD620() async {
        let fake = FakeWebhookService()
        let model = WebhookSettingsModel(service: fake)
        model.webhookUrl = " https://hooks.test/b "
        fake.saveAnswer = WebhookSettingsSaveResponse(success: true, webhookSecret: "whsec_1",
                                                      secretRegenerated: nil, message: nil)
        fake.settings = WebhookSettings(configured: true, webhookUrl: "https://hooks.test/b")

        await model.save()
        XCTAssertEqual(fake.saved.first?.webhookUrl, "https://hooks.test/b")
        XCTAssertEqual(model.newSecret, "whsec_1")
        XCTAssertTrue(model.settings.configured)
    }
}

private final class FakeWebhookService: WebhookSettingsServicing {
    var settings = WebhookSettings.unconfigured
    var saveAnswer = WebhookSettingsSaveResponse(success: true, webhookSecret: nil,
                                                 secretRegenerated: nil, message: nil)
    private(set) var saved: [UpdateWebhookSettingsRequest] = []
    private(set) var deletes = 0

    func getWebhookSettings() async throws -> WebhookSettings { settings }

    func updateWebhookSettings(_ request: UpdateWebhookSettingsRequest) async throws -> WebhookSettingsSaveResponse {
        saved.append(request)
        return saveAnswer
    }

    func deleteWebhookSettings() async throws { deletes += 1 }

    func testWebhook() async throws -> WebhookTestResult {
        WebhookTestResult(success: true, message: nil, responseTime: 12, statusCode: 200, error: nil)
    }
}
