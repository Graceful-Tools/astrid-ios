//  SidebarProjectCollapseTests.swift
//  ADEV-57: "enable projects to hide/show the lists in project".

import XCTest
@testable import Astrid_App

@MainActor
final class SidebarProjectCollapseTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "SidebarProjectCollapseTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAProjectShowsItsListsUntilHidden_ADEV57() {
        let collapse = SidebarProjectCollapse(defaults: defaults)
        XCTAssertFalse(collapse.isCollapsed("dev"))
        XCTAssertEqual(collapse.visibleLists(["web", "ios"], in: "dev"), ["web", "ios"])
    }

    func testTheChevronHidesAndShowsOnlyThatProjectsLists_ADEV57() {
        let collapse = SidebarProjectCollapse(defaults: defaults)
        collapse.toggle("dev")
        XCTAssertEqual(collapse.visibleLists(["web", "ios"], in: "dev"), [])
        XCTAssertEqual(collapse.visibleLists(["home"], in: "family"), ["home"], "other projects stay open")
        collapse.toggle("dev")
        XCTAssertEqual(collapse.visibleLists(["web", "ios"], in: "dev"), ["web", "ios"])
    }

    func testWhatWasHiddenIsRememberedOnThisDevice_ADEV57() {
        SidebarProjectCollapse(defaults: defaults).toggle("dev")
        XCTAssertTrue(SidebarProjectCollapse(defaults: defaults).isCollapsed("dev"))
    }

    func testTheChevronSaysWhatItWillDo_ADEV57() {
        let collapse = SidebarProjectCollapse(defaults: defaults)
        XCTAssertEqual(collapse.toggleLabel(for: "dev", name: "Astrid-Dev"), "Hide lists in Astrid-Dev")
        collapse.toggle("dev")
        XCTAssertEqual(collapse.toggleLabel(for: "dev", name: "Astrid-Dev"), "Show lists in Astrid-Dev")
    }
}
