//  MacSharedDesignViewsTests.swift
//  ADEV-166: one pill, one Done header and one empty state, shared by iOS and the Mac. iOS is the
//  reference: a pill's wash is iOS's 15%, the Done header is iOS's capsule, and the Mac follows.

import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacSharedDesignViewsTests: XCTestCase {

    func testADEV166_thePillIsTheIOSCapsule() {
        XCTAssertEqual(AstridPill.fillOpacity, 0.15)
        XCTAssertEqual(AstridPill.strokeOpacity, 0.4)
        XCTAssertEqual(AstridPill.strokeWidth, 1)
        _ = AstridPill(text: "Ready", tint: Theme.success)
    }

    func testADEV166_theMacBuildsTheSharedHeaderBadgeAndEmptyState() {
        _ = BoardHeaderBadge { Text(verbatim: "3") }
        _ = AstridSpeechBubble(message: "Nothing here", density: .compact)
        XCTAssertLessThan(EmptyStateDensity.compact.artSize, EmptyStateDensity.regular.artSize)
        XCTAssertEqual(EmptyStateDensity.regular.artSize, 160, "iOS keeps its 160 pt art")
    }

    func testADEV166_theMacBoardDrawsTheDoneHeaderAndEmptyColumnThroughTheSharedViews() throws {
        let board = try RepositoryLocator.source(at: "Astrid Mac/Views/MacBoardView.swift")
        XCTAssertTrue(board.contains("BoardHeaderBadge"), "the Done header takes iOS's capsule")
        XCTAssertTrue(board.contains("AstridSpeechBubble("), "an empty column is the shared empty state")
        let empty = try RepositoryLocator.source(at: "Astrid Mac/Views/MacEmptyState.swift")
        XCTAssertTrue(empty.contains("AstridSpeechBubble("))
    }
}

/// ADEV-170: the quick changer's frame and the sidebar Projects section, one implementation each.
final class MacSharedQuickChangerProjectsTests: XCTestCase {

    func testADEV170_theMacQuickChangerTakesIOSsFrame() throws {
        XCTAssertEqual(QuickChangerLayout.width, 280)
        XCTAssertEqual(QuickChangerLayout.padding, Theme.spacing16)
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacQuickChanger.swift")
        XCTAssertTrue(source.contains("QuickChangerFrame"))
        XCTAssertTrue(source.contains("QuickChangerSection("))
        XCTAssertFalse(source.contains(".frame(width: 240)"))
    }

    func testADEV170_theMacProjectsSectionDrawsThroughTheSharedSectionAndHeader() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacProjectSelection.swift")
        XCTAssertTrue(source.contains("SidebarProjectSections("))
        XCTAssertTrue(source.contains("SidebarProjectHeaderTitle("))
        XCTAssertTrue(source.contains("SidebarProjectCollapseToggle("))
        XCTAssertFalse(source.contains("chevron.right"))
    }
}
