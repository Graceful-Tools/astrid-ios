//  MacDesignParityTests.swift
//  ADEV-60: "do a full design review and make sure we identify and fix where new updates caused
//  interface design to diverge. iOS / mac are probably still the best." Where the Mac had its own
//  copy of a rule iOS reads from Core, or drew what iOS stopped drawing.

import XCTest
@testable import Astrid_Mac

final class MacDesignParityTests: XCTestCase {

    func testTaskRowChipsAreTheCoresAnswerAsOnIOS_ADEV60() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacTaskRow.swift")
        XCTAssertTrue(source.contains("chipListsForTaskRow("), "the core's listChips, not a Mac filter")
    }

    func testDoneHasNoAddATaskBarAsOnIOS_ADEV60() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacBoardView.swift")
        XCTAssertTrue(source.contains("if col.kind != .done { addCardField(col) }"))
    }

    func testSidebarSharesFavoritesOrderAndPrivacyGlyphWithIOS_ADEV60() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/App/MacRootView.swift")
        XCTAssertTrue(source.contains("SidebarFavorites.ordered("))
        XCTAssertTrue(source.contains("ListPrivacyGlyph("))
    }

    func testThePopoutArrowIsTheSharedOne_ADEV60() {
        XCTAssertEqual(MacLayout.detailArrowWidth, DetailPanelChrome.arrowWidth)
        XCTAssertEqual(MacLayout.arrowOverlap, DetailPanelChrome.arrowOverlap)
    }

    func testTheBoardColumnAddBarSaysWhatIOSSays_ADEV60() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacQuickAddBar.swift")
        XCTAssertTrue(source.contains("\"tasks.add_task_placeholder\""))
    }
}
