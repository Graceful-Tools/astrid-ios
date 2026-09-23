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

    func testTask_920155a6AgentRowsMatchWebIdentityContract() throws {
        let rows = AgentRuntimeRow.all

        XCTAssertEqual(rows.map(\.id), ["claude", "codex", "muse", "copilot", "gemini"])
        XCTAssertEqual(rows.map(\.modeMailbox), ["claude", "openai", "muse", "copilot", "gemini"])

        let codex = try XCTUnwrap(rows.first { $0.id == "codex" })
        XCTAssertEqual(codex.identityMailbox(for: .polling), "codex")
        XCTAssertEqual(codex.identityMailbox(for: .api), "openai")
        XCTAssertEqual(codex.identityMailbox(for: .webhook), "openai")
        XCTAssertEqual(codex.identityMailbox(for: .off), "openai")
    }

    /// Muse Code is a local CLI (Meta, August 2026) — there is no Meta API Astrid calls, so the
    /// row is HARNESS-ONLY: no credential, no server executor, no webhook to push to. Web has
    /// had it since AWTD-937 (lib/ai/harness-agents.ts); mobile listed four agents and not this
    /// one, which is the whole of task d0b5f7ae.
    func testTask_d0b5f7aeMuseIsAnAgentInSettingsAndIsHarnessOnly() throws {
        let muse = try XCTUnwrap(
            AgentRuntimeRow.all.first { $0.id == "muse" },
            "Muse must be one of the agents the hub lists"
        )

        XCTAssertEqual(muse.label, "Muse")
        XCTAssertEqual(muse.modeMailbox, "muse")
        XCTAssertEqual(muse.pollMailbox, "muse")
        XCTAssertEqual(muse.service, "muse")
        XCTAssertFalse(muse.usesOAuth, "Muse authenticates in its own CLI, not through Astrid")

        // Unlike the Codex row — openai@ under Astrid, codex@ when polling — Muse has only ever
        // one identity, because only one runtime can ever run it.
        for mode in AgentExecutionMode.allCases {
            XCTAssertEqual(muse.identityMailbox(for: mode), "muse", "\(mode.rawValue) must stay muse@")
        }

        // The point of the flag: "Astrid runs it" is a button whose PUT the server rejects, and
        // under "I run it" there is exactly one transport, so neither picker should offer more.
        XCTAssertTrue(muse.isHarnessOnly)
        XCTAssertEqual(muse.availableOwnerships, [.user, .off])
        XCTAssertEqual(muse.availableTransports, [.polling])

        // Every provider-backed row keeps all three choices — locking is per agent, not global.
        for row in AgentRuntimeRow.all where !row.isHarnessOnly {
            XCTAssertEqual(row.availableOwnerships, AgentOwnership.allCases, "\(row.id)")
            XCTAssertEqual(row.availableTransports, AgentSelfTransport.allCases, "\(row.id)")
        }
        XCTAssertEqual(
            AgentRuntimeRow.all.filter { $0.isHarnessOnly }.map(\.id), ["muse"],
            "the Codex row is NOT harness-only — its mode mailbox is openai, which has an executor"
        )
    }

    /// Muse parses options on the SUBCOMMAND rather than the root, so its cron line is not
    /// Codex's with the binary swapped. Mirrors the web tab in components/agent-runtime-settings.tsx.
    func testTask_d0b5f7aeMuseRecipeMatchesTheWebSetupCopy() {
        let recipes = AgentHarnessRecipes.recipes(
            for: "muse",
            origin: "https://astrid.cc",
            serverName: "astrid"
        )
        let text = recipes.flatMap(\.steps).joined(separator: "\n")

        XCTAssertFalse(recipes.isEmpty, "Muse must explain how its harness polls")
        XCTAssertTrue(text.contains("muse mcp add astrid --url https://astrid.cc/mcp"))
        XCTAssertTrue(text.contains("muse mcp login astrid"))
        XCTAssertTrue(text.contains("muse exec"), "the cron line runs the exec subcommand")
        XCTAssertTrue(
            text.contains("--disable-approval"),
            "an unattended run cannot answer an approval prompt"
        )
        XCTAssertFalse(text.contains("codex exec"), "Muse is not Codex with the binary swapped")
    }

    /// A Muse byline should carry the brand mark, the same as every other agent identity.
    func testTask_d0b5f7aeMuseAgentUserResolvesItsBrandIcon() {
        for type in ["muse", "muse_agent"] {
            let user = User(id: "u", email: "muse@astrid.cc", name: "Muse Agent", image: nil,
                            isAIAgent: true, aiAgentType: type)
            XCTAssertEqual(user.agentBrandImageAsset, "ai-muse", type)
        }
    }

    // MARK: - AITD-424: Muse's brand mark

    private func agentAsset(_ imageset: String, _ file: String) throws -> String {
        try String(
            contentsOf: RepositoryLocator.root
                .appendingPathComponent("Astrid App/Assets.xcassets/\(imageset).imageset/\(file)"),
            encoding: .utf8
        )
    }

    /// AITD-424: `ai-muse` shipped a redrawn infinity loop rather than Meta's mark. Web's icon
    /// table (`lib/ai/harness-agents.ts`) names the simple-icons `meta` slug in `#0467DF`, and
    /// every other bundled fallback is that slug's path copied verbatim — iOS never calls the
    /// `/api/v1/agent-icon` proxy, so whatever is in the catalog is what the phone shows forever.
    func testAITD424_TheMuseAssetCarriesMetasOfficialMark() throws {
        let muse = try agentAsset("ai-muse", "muse.svg")

        XCTAssertTrue(muse.contains("M6.915 4.03c-1.968"),
                      "ai-muse must be the simple-icons `meta` path, not a redraw of it")
        XCTAssertFalse(muse.contains("M6.2 5.5c-2.6"),
                       "the hand-drawn stand-in must be gone")
        XCTAssertTrue(muse.contains("#0467DF"), "Meta brand blue, as web's icon table specifies")
    }

    /// AITD-424: web applies `padding: 0.125` in the proxy; iOS has no proxy, so the padding is
    /// baked into the catalog copy — `ai-copilot` already does this. Unpadded, the hub's
    /// `.clipShape(Circle())` crops the outer edges of the mark.
    func testAITD424_TheMuseAssetIsPaddedLikeTheOtherClippedMarks() throws {
        let muse = try agentAsset("ai-muse", "muse.svg")
        let copilot = try agentAsset("ai-copilot", "copilot.svg")

        func viewBox(_ svg: String) -> String? {
            guard let range = svg.range(of: #"viewBox="[^"]*""#, options: .regularExpression)
            else { return nil }
            return String(svg[range])
        }

        XCTAssertEqual(viewBox(copilot), #"viewBox="-3 -3 30 30""#, "the padding convention itself")
        XCTAssertEqual(viewBox(muse), viewBox(copilot),
                       "a mark clipped to a circle needs the same breathing room as Copilot's")
    }

    /// AITD-424: the agent-icon endpoint serves SVG, which `PlatformImage` cannot decode, so a
    /// Muse byline must resolve to the bundled vector instead of attempting a network load.
    /// The resolver knew only `copilot`; every other agent drew blank.
    func testAITD424_TheMuseAgentIconURLResolvesToTheBundledAsset() {
        let museURL = URL(string: "https://astrid.cc/api/v1/agent-icon/muse")!
        XCTAssertEqual(AgentAvatarAsset.assetName(for: museURL), "ai-muse")

        for (slug, asset) in [("claude", "ai-claude"), ("openai", "ai-openai"),
                              ("gemini", "ai-gemini"), ("copilot", "ai-copilot")] {
            let url = URL(string: "https://astrid.cc/api/v1/agent-icon/\(slug)")!
            XCTAssertEqual(AgentAvatarAsset.assetName(for: url), asset,
                           "\(slug) has a bundled mark too")
        }

        XCTAssertNil(AgentAvatarAsset.assetName(for: URL(string: "https://astrid.cc/avatars/x.png")!),
                     "only the agent-icon endpoint is resolved locally")
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
        let root = RepositoryLocator.root
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Views/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AgentHubView()"))
        XCTAssertTrue(source.contains("\"settings.agents.title\""))
    }
}
