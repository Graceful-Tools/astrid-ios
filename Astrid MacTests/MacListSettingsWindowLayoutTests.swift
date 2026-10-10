//  MacListSettingsWindowLayoutTests.swift
//  Regression guard for AITD-483 — List Settings opened with its title and Done cut off.
//
//  The window is a fixed size and its content was not: the Filters tab's form insisted on 360pt
//  with a note, two toggles and Clear stacked around it, about 120pt more than the window had.
//  SwiftUI centres what does not fit, so the overflow came off BOTH ends — the title at the top,
//  Done at the bottom — and everything between sat at the wrong height.
//
//  So the claim tested is the layout one, against the real views rather than their source: offered
//  the window's size, the content asks for no more than the window's size.

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import Astrid_Mac

final class MacListSettingsWindowLayoutTests: XCTestCase {

    /// The height the window's content takes when it is offered `size` — the window, by default.
    @MainActor private func contentHeight(on tab: MacListSettingsWindow.Tab,
                                          offered size: CGSize = MacListSettingsWindow.size) -> CGFloat {
        let window = MacListSettingsWindow(list: TaskList(id: "aitd-483", name: "Groceries"),
                                           initialTab: tab)
        let host = NSHostingController(rootView: window.content)
        return host.sizeThatFits(in: size).height
    }

    /// The reported case: Filters is the tab the window opens on.
    @MainActor
    func testAITD483_theFiltersTabFitsTheWindowSoTheTitleAndDoneAreNotClipped() {
        XCTAssertLessThanOrEqual(contentHeight(on: .sortFilters), MacListSettingsWindow.size.height,
                                 "AITD-483: content taller than the window is centred, clipping the title and Done")
    }

    /// Fitting must not be a lucky number. Offered the 560pt the window used to be — less than
    /// the 667pt the tab wants — the form gives up the difference instead of the title and Done.
    /// A bigger text size (View ▸ Bigger) is the same squeeze from the other side.
    @MainActor
    func testAITD483_theFiltersTabShrinksIntoAShorterWindowInsteadOfOverflowingIt() {
        let shorter = CGSize(width: MacListSettingsWindow.size.width, height: 560)
        XCTAssertLessThanOrEqual(contentHeight(on: .sortFilters, offered: shorter), shorter.height,
                                 "AITD-483: the filter form flexes; the window's own controls do not get clipped")
    }

    /// Admin stacks every list-level section with nothing to scroll them — the same overflow,
    /// one tab over.
    @MainActor
    func testAITD483_theAdminTabFitsTheWindow() {
        XCTAssertLessThanOrEqual(contentHeight(on: .admin), MacListSettingsWindow.size.height,
                                 "AITD-483: the Admin tab must scroll rather than outgrow the window")
    }

    @MainActor
    func testAITD483_theMembershipTabFitsTheWindow() {
        XCTAssertLessThanOrEqual(contentHeight(on: .membership), MacListSettingsWindow.size.height,
                                 "AITD-483: the Membership tab must fit the window")
    }
}
#endif
