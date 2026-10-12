import XCTest
@testable import Astrid_App

/// AITD-491 — the multi-select assignee picker for lists where `supports.multipleAssignees` is
/// true. The rule for what a tap does is shared by iOS and the Mac.
final class AssigneeSelectionTests: XCTestCase {

    private func list(_ id: String, multiple: Bool) -> TaskList {
        TaskList(id: id, name: id, supports: multiple ? ListSupports(multipleAssignees: true) : nil)
    }

    func test_aitd491_onlyAListThatSaysSoAllowsSeveralAssignees() {
        let lists = [list("classic", multiple: false), list("board", multiple: true)]
        XCTAssertFalse(AssigneeSelection.allowsMultiple(listIds: ["classic"], lists: lists))
        XCTAssertTrue(AssigneeSelection.allowsMultiple(listIds: ["classic", "board"], lists: lists))
        XCTAssertFalse(AssigneeSelection.allowsMultiple(listIds: [], lists: lists))
        XCTAssertFalse(AssigneeSelection.allowsMultiple(listIds: ["unknown"], lists: lists))
    }

    func test_aitd491_tappingSomeoneNewAddsThemAfterThePrimary() {
        XCTAssertEqual(AssigneeSelection.toggling("u2", in: ["u1"]), ["u1", "u2"])
        XCTAssertEqual(AssigneeSelection.toggling("u1", in: []), ["u1"])
    }

    func test_aitd491_tappingSomeoneAssignedRemovesThem_andTheNextBecomesPrimary() {
        XCTAssertEqual(AssigneeSelection.toggling("u1", in: ["u1", "u2", "u3"]), ["u2", "u3"])
        XCTAssertEqual(AssigneeSelection.toggling("u1", in: ["u1"]), [])
    }

    func test_aitd491_unassignedClearsEveryone() {
        XCTAssertEqual(AssigneeSelection.toggling(nil, in: ["u1", "u2"]), [])
        XCTAssertEqual(AssigneeSelection.toggling("", in: ["u1", "u2"]), [])
    }

    /// The server refuses an agent anywhere but first, and there is only one first.
    func test_aitd491_anAgentGoesFirstAndReplacesAnotherAgent() {
        let agents: Set<String> = ["ai-claude", "ai-codex"]
        XCTAssertEqual(AssigneeSelection.toggling("ai-claude", in: ["u1", "u2"], agentIds: agents),
                       ["ai-claude", "u1", "u2"])
        XCTAssertEqual(AssigneeSelection.toggling("ai-codex", in: ["ai-claude", "u1"], agentIds: agents),
                       ["ai-codex", "u1"])
        XCTAssertEqual(AssigneeSelection.toggling("u2", in: ["ai-claude", "u1"], agentIds: agents),
                       ["ai-claude", "u1", "u2"], "a person never displaces the agent")
    }

    func test_aitd491_anEleventhPersonIsNotAdded_butAnyoneCanStillBeRemoved() {
        let ten = (1...10).map { "u\($0)" }
        XCTAssertEqual(AssigneeSelection.toggling("u11", in: ten), ten)
        XCTAssertEqual(AssigneeSelection.toggling("u10", in: ten).count, 9)
    }

    func test_aitd491_facesAfterThePrimaryAreCappedAndTheRestCounted() {
        let two = AssigneeSelection.additionalFaces(in: ["u1", "u2"])
        XCTAssertEqual(two.shown, ["u2"])
        XCTAssertEqual(two.overflow, 0)
        let six = AssigneeSelection.additionalFaces(in: ["u1", "u2", "u3", "u4", "u5", "u6"])
        XCTAssertEqual(six.shown, ["u2", "u3", "u4"])
        XCTAssertEqual(six.overflow, 2)
        XCTAssertTrue(AssigneeSelection.additionalFaces(in: []).shown.isEmpty)
    }
}
