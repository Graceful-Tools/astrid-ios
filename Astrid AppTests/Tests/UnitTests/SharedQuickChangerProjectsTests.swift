//  SharedQuickChangerProjectsTests.swift
//  ADEV-170: one quick changer frame and one sidebar Projects section, shared by iOS and the Mac.
//  iOS is the reference: 280 wide with 16 padding, and the Projects header's name and chevron.

import SwiftUI
import XCTest
@testable import Astrid_App

final class SharedQuickChangerProjectsTests: XCTestCase {

    func testADEV170_theQuickChangerFrameIsIOSs280By16() {
        XCTAssertEqual(QuickChangerLayout.width, 280)
        XCTAssertEqual(QuickChangerLayout.padding, Theme.spacing16)
        XCTAssertEqual(QuickChangerLayout.spacing, Theme.spacing16)
        _ = QuickChangerFrame { Text(verbatim: "x") }
        _ = QuickChangerSection(title: "Project state") { Text(verbatim: "x") }
    }

    func testADEV170_theIOSQuickChangerDrawsThroughTheSharedFrame() throws {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Components/TaskQuickChanger.swift")
        XCTAssertTrue(source.contains("QuickChangerFrame"))
        XCTAssertFalse(source.contains(".frame(width: 280)"), "the width is stated once, in QuickChangerLayout")
    }

    func testADEV170_theIOSProjectsSectionDrawsThroughTheSharedSectionAndHeader() throws {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Lists/ListProjectViews.swift")
        XCTAssertTrue(source.contains("SidebarProjectSections("))
        XCTAssertTrue(source.contains("SidebarProjectHeaderTitle("))
        XCTAssertTrue(source.contains("SidebarProjectCollapseToggle("))
        XCTAssertFalse(source.contains("chevron.right"), "the chevron is drawn once, in the shared toggle")
    }
}
