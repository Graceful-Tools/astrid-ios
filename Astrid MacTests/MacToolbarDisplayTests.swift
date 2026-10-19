//  MacToolbarDisplayTests.swift
//  Astrid for Mac — AITD-510: no "Icon and Text / Icon Only" menu on the window toolbar.

#if os(macOS)
import AppKit
import XCTest
@testable import Astrid_Mac

@MainActor
final class MacToolbarDisplayTests: XCTestCase {

    /// AITD-510: "remove the 'icons only' 'icons and text' menu — should only be icons only."
    ///
    /// Right-clicking the window toolbar offered AppKit's display-mode menu. Picking "Icon and
    /// Text" put labels under every button; the app is designed icons-only.
    func testTheToolbarIsIconsOnlyAndOffersNoDisplayModeMenuAITD510() {
        let toolbar = NSToolbar(identifier: "aitd-510")
        toolbar.displayMode = .iconAndLabel
        if #available(macOS 15.0, *) { toolbar.allowsDisplayModeCustomization = true }

        MacToolbarDisplay.lockToIconsOnly(toolbar)

        XCTAssertEqual(toolbar.displayMode, .iconOnly)
        if #available(macOS 15.0, *) {
            XCTAssertFalse(toolbar.allowsDisplayModeCustomization,
                           "AITD-510: the right-click Icon and Text / Icon Only menu must not be offered")
        }
        XCTAssertFalse(toolbar.allowsUserCustomization)
    }
}
#endif
