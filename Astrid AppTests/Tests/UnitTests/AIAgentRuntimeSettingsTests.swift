import XCTest
@testable import Astrid_App

@MainActor
final class AIAgentRuntimeSettingsTests: XCTestCase {
    func testTask_920155a6ModeWireValuesMatchWeb() throws {
        XCTAssertEqual(AgentExecutionMode.allCases.map(\.rawValue), [
            "api", "polling", "webhook", "off",
        ])

        let request = UpdateAgentModeRequest(agent: "openai", mode: .polling)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String]
        )
        XCTAssertEqual(object, ["agent": "openai", "mode": "polling"])
    }

    func testTask_920155a6AgentRowsMatchWebIdentityContract() {
        let rows = AgentRuntimeRow.all

        XCTAssertEqual(rows.map(\.id), ["claude", "codex", "copilot", "gemini"])
        XCTAssertEqual(rows.map(\.modeMailbox), ["claude", "openai", "copilot", "gemini"])

        let codex = rows[1]
        XCTAssertEqual(codex.identityMailbox(for: .polling), "codex")
        XCTAssertEqual(codex.identityMailbox(for: .api), "openai")
        XCTAssertEqual(codex.identityMailbox(for: .webhook), "openai")
        XCTAssertEqual(codex.identityMailbox(for: .off), "openai")
    }

    func testTask_920155a6AgentModesResponseDecodesVersionedContract() throws {
        let json = """
        {
          "agents": [
            {"mailbox":"claude","email":"claude@astrid.cc","mode":"polling","locked":false}
          ],
          "modes": {"claude":"polling","openai":"api","copilot":"off","gemini":"webhook"},
          "meta": {"apiVersion":"v1","authSource":"oauth"}
        }
        """

        let response = try JSONDecoder().decode(AgentModesResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.agents.first?.mailbox, "claude")
        XCTAssertEqual(response.modes["openai"], .api)
        XCTAssertEqual(response.modes["gemini"], .webhook)
    }

    func testTask_920155a6PollingRecipesUseTheRowsPollingMailbox() {
        for row in AgentRuntimeRow.all {
            let recipes = AgentHarnessRecipes.recipes(
                for: row.pollMailbox,
                origin: "https://astrid.cc",
                serverName: "astrid"
            )
            XCTAssertFalse(recipes.isEmpty, "\(row.id) must explain how its harness polls")
            XCTAssertTrue(
                recipes.flatMap(\.steps).joined(separator: "\n")
                    .contains("agent \"\(row.pollMailbox)\""),
                "\(row.id) recipes must claim only the correct queue identity"
            )
        }
    }

    func testTask_920155a6CopilotRecipesCoverLocalAndCIHarnesses() {
        let recipes = AgentHarnessRecipes.recipes(
            for: "copilot",
            origin: "https://astrid.cc",
            serverName: "astrid"
        )
        let text = recipes.flatMap(\.steps).joined(separator: "\n")

        XCTAssertTrue(text.contains("\"servers\""), "VS Code needs its mcp.json configuration")
        XCTAssertTrue(text.contains(".github/workflows/astrid-queue.yml"))
        XCTAssertTrue(text.contains("schedule:"))
        XCTAssertTrue(text.contains("secrets.ASTRID_TOKEN"))
        XCTAssertTrue(text.contains("empty == 'false'"))
    }

    func testTask_920155a6SettingsExposesAgentRuntimePage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Views/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AgentHubView()"))
        XCTAssertTrue(source.contains("\"settings.agents.title\""))
    }
}
