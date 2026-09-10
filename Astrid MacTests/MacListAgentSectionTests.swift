//  MacListAgentSectionTests.swift
//  Task AITD-380 — "Mac has no AI agents list-settings screen."
//
//  The behaviour of the write is pinned in `ListAgentSettingsTests` (the shared target, since
//  both platforms send it). What is Mac-specific is the three things that make this a real
//  setting rather than another control that looks live: it is REACHABLE, it is GATED by the
//  shared permission rule, and it writes through the SERVICE.
//
//  All three are asserted against the source. That is the same instrument
//  `MacBoardPriorityStallTests` uses, and it is the right one here: a SwiftUI `if canEdit`
//  branch cannot be observed from a unit test, but "did anyone hand-roll the rule" can be —
//  and hand-rolling it is the specific failure this task's own description warned about.

import XCTest
@testable import Astrid_Mac

final class MacListAgentSectionTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func sectionSource() throws -> String {
        try source("Astrid Mac/Views/MacListAgentSection.swift")
    }

    // MARK: - Reachable

    func testTheListEditSheetActuallyRendersTheSection() throws {
        // The acceptance criterion is "reachable from the same menu on the sidebar and a board".
        // `.edit` is already in `MacListMenu` on both surfaces, so embedding it here is what
        // makes it reachable from both — and a section nothing renders is not a feature.
        XCTAssertTrue(try source("Astrid Mac/Views/MacListEditSheet.swift")
                        .contains("MacListAgentSection(list:"),
                      "the edit sheet must render the agent section, or nothing opens it")
    }

    func testTheSectionIsOfferedOnlyForAnExistingList() throws {
        // It writes to a list id, so it cannot appear while CREATING one. The sheet's
        // `if let existingList = existing` branch is what guarantees that.
        let sheet = try source("Astrid Mac/Views/MacListEditSheet.swift")
        let branch = try XCTUnwrap(sheet.range(of: "if let existingList = existing"))
        let call = try XCTUnwrap(sheet.range(of: "MacListAgentSection(list: existingList)"))
        XCTAssertTrue(branch.lowerBound < call.lowerBound,
                      "the section must sit inside the existing-list branch")
    }

    // MARK: - Gated by the SHARED rule

    func testThePermissionRuleIsAskedNotRestated() throws {
        XCTAssertTrue(try sectionSource().contains("ListPermissions.canEditSettings"),
                      "the gate must be the shared rule — it is a contract with Web")
    }

    func testTheSectionDoesNotHandRollARoleComparison() throws {
        // The rule was written out three separate times before `ListPermissions` existed, and
        // one of those copies was wrong. A fourth would be the same bug again.
        let section = try sectionSource()
        for handRolled in ["== \"admin\"", "== \"owner\"", "role == ", "ownerId =="] {
            XCTAssertFalse(section.contains(handRolled),
                           "restates the permission rule instead of asking ListPermissions: \(handRolled)")
        }
    }

    // MARK: - Writes through the service

    func testTheSectionWritesThroughTheServiceControlPoint() throws {
        let section = try sectionSource()
        XCTAssertTrue(section.contains("ListService.shared.setListDefaultAgent"),
                      "the write must go through the service's control point (ASTRID.md §0 rule 1)")
        // The CALL form, as `CanonicalControlPointsTests` audits it on iOS. Matching the bare
        // type name would fail on a comment that says not to use it.
        XCTAssertFalse(section.contains("AstridAPIClient.shared"),
                       "a view must never call the API client directly")
    }

    func testTheSectionDoesNotBuildTheAgentConfigItself() throws {
        // Building it inline is how the enabled types get erased: `aiAgentConfig` REPLACES the
        // stored config, so the current types have to be carried forward. That merge belongs to
        // `ListAgentSettings`, which the service uses — see ListAgentSettingsTests.
        XCTAssertFalse(try sectionSource().contains("ListAgentConfig("),
                       "the config must come from ListAgentSettings, not be assembled in the view")
    }

    // MARK: - Copy is localized

    func testTheSectionUsesLocalizedCopy() throws {
        let section = try sectionSource()
        XCTAssertTrue(section.contains("lists.ai_agent.section"))
        XCTAssertTrue(section.contains("lists.ai_agent.account_default"))
        // Localizable.strings keys are a cross-platform registry with Web, so user-visible text
        // is never a literal here (ASTRID.md §0 rule 8).
        XCTAssertFalse(section.contains("Text(\"AI Agent\")"))
    }
}
