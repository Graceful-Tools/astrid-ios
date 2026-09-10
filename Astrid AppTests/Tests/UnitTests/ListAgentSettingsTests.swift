import XCTest
@testable import Astrid_App

/// Task AITD-380 — "Mac has no AI agents list-settings screen."
///
/// The screen is the visible half. The half that bites is the write: on
/// `PUT /api/v1/lists/[id]` the server REPLACES the stored agent config from
/// whatever `aiAgentConfig` the client sends (`storedAgentConfig`, web's
/// `app/api/v1/lists/[id]/route.ts:252`). A client that sends only the field it
/// changed therefore erases the fields it left out.
///
/// Web's own picker carries the current types forward by hand —
/// `const currentTypes = list.aiAgentConfig?.enabledTypes ?? list.aiAgentsEnabled ?? []`
/// (`components/list-admin/ListAiAgentSection.tsx`). That line is the contract,
/// and remembering it at each call site is how one platform eventually forgets.
/// It lives here instead, so iOS and Mac cannot disagree about what a
/// default-agent change sends.
final class ListAgentSettingsTests: XCTestCase {

    private func list(enabledTypes: [String]? = nil,
                      defaultAgentId: String? = nil,
                      legacyArray: [String]? = nil) -> TaskList {
        var list = TaskList(id: "l1", name: "Work")
        if enabledTypes != nil || defaultAgentId != nil {
            list.aiAgentConfig = ListAgentConfig(enabledTypes: enabledTypes ?? [],
                                                 defaultAgentId: defaultAgentId)
        }
        list.aiAgentsEnabled = legacyArray
        return list
    }

    // MARK: - The wipe this exists to prevent

    func testChangingTheDefaultAgentKeepsTheEnabledTypes() {
        let config = ListAgentSettings.settingDefaultAgent(
            "agent-7",
            on: list(enabledTypes: ["claude", "codex"], defaultAgentId: nil)
        )

        XCTAssertEqual(config.enabledTypes, ["claude", "codex"],
                       "Sending [] for enabledTypes erases them server-side")
        XCTAssertEqual(config.defaultAgentId, "agent-7")
    }

    func testClearingTheDefaultAgentAlsoKeepsTheEnabledTypes() {
        // "Use account default" is a null defaultAgentId, not an empty config.
        let config = ListAgentSettings.settingDefaultAgent(
            nil,
            on: list(enabledTypes: ["claude"], defaultAgentId: "agent-7")
        )

        XCTAssertEqual(config.enabledTypes, ["claude"])
        XCTAssertNil(config.defaultAgentId)
    }

    // MARK: - Where the current types are read from

    func testFallsBackToTheLegacyArrayWhenThereIsNoConfigObject() {
        // On the wire `aiAgentsEnabled` is the plain string[] and the default
        // agent rides in `aiAgentConfig`. A list cached before the object was
        // served has only the array, and it is still the truth about types.
        let config = ListAgentSettings.settingDefaultAgent(
            "agent-7",
            on: list(legacyArray: ["claude"])
        )

        XCTAssertEqual(config.enabledTypes, ["claude"])
    }

    func testTheConfigObjectWinsOverTheLegacyArray() {
        let config = ListAgentSettings.settingDefaultAgent(
            "agent-7",
            on: list(enabledTypes: ["codex"], defaultAgentId: nil, legacyArray: ["claude"])
        )

        XCTAssertEqual(config.enabledTypes, ["codex"])
    }

    func testAListWithNoAgentFieldsAtAllSendsNoTypes() {
        let config = ListAgentSettings.settingDefaultAgent("agent-7", on: list())

        XCTAssertEqual(config.enabledTypes, [])
        XCTAssertEqual(config.defaultAgentId, "agent-7")
    }

    func testAnEmptyConfigObjectIsNotTreatedAsAbsent() {
        // `enabledTypes: []` recorded on the list is a real answer — "no types" —
        // and must not fall through to a stale legacy array.
        let config = ListAgentSettings.settingDefaultAgent(
            "agent-7",
            on: list(enabledTypes: [], defaultAgentId: nil, legacyArray: ["claude"])
        )

        XCTAssertEqual(config.enabledTypes, [])
    }

    // MARK: - Reading the current selection back

    func testTheCurrentAgentComesFromTheConfigObject() {
        XCTAssertEqual(
            ListAgentSettings.currentDefaultAgentId(on: list(enabledTypes: ["claude"],
                                                            defaultAgentId: "agent-7")),
            "agent-7"
        )
    }

    func testNoConfiguredAgentReadsAsNil() {
        XCTAssertNil(ListAgentSettings.currentDefaultAgentId(on: list(legacyArray: ["claude"])))
    }

    func testAnEmptyAgentIdReadsAsNilRatherThanAnAgentNamedEmptyString() {
        // The picker tags "use account default" with "", and a round-trip could
        // store that. It means the same thing as absent and must select the same
        // row, or the picker renders with nothing selected.
        XCTAssertNil(ListAgentSettings.currentDefaultAgentId(
            on: list(enabledTypes: [], defaultAgentId: "")))
    }

    // MARK: - The request the service sends

    func testTheUpdateRequestCarriesTheConfigAndNothingElse() {
        // Every other field must stay nil: PUT applies what it is given, so a
        // populated field here would write a value the user did not touch.
        let request = ListAgentSettings.updateRequest(
            settingDefaultAgent: "agent-7",
            on: list(enabledTypes: ["claude"], defaultAgentId: nil)
        )

        XCTAssertEqual(request.aiAgentConfig?.defaultAgentId, "agent-7")
        XCTAssertEqual(request.aiAgentConfig?.enabledTypes, ["claude"])
        XCTAssertNil(request.name)
        XCTAssertNil(request.description)
        XCTAssertNil(request.color)
        XCTAssertNil(request.privacy)
    }

    func testTheEncodedBodySendsAiAgentConfigAndOmitsUntouchedFields() throws {
        // The server distinguishes "absent" from "null", so an encoder that
        // emitted every key would clear the fields it named.
        let request = ListAgentSettings.updateRequest(
            settingDefaultAgent: nil,
            on: list(enabledTypes: ["claude"], defaultAgentId: "agent-7")
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )

        let config = try XCTUnwrap(json["aiAgentConfig"] as? [String: Any])
        XCTAssertEqual(config["enabledTypes"] as? [String], ["claude"])
        XCTAssertNil(json["name"])
        XCTAssertNil(json["color"])
    }
}
