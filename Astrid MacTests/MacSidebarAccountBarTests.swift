//  MacSidebarAccountBarTests.swift
//  The sidebar's gear opens Settings, and nothing else (ADEV-78).
//
//  Jon: "profile should be accessible from setting icon. there should not be a chevron and quick
//  menu on gear for settings." The gear was a borderless Menu — Settings / Profile / Sign Out —
//  which draws a chevron beside the icon. It is a plain SettingsLink now; Settings ▸ Account
//  carries your profile (your photo opens it) and Sign Out.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSidebarAccountBarTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        try RepositoryLocator.source(at: path)
    }

    func testTheGearIsASettingsLinkWithNoMenu_ADEV78() throws {
        let bar = try source("Astrid Mac/Views/MacSidebarAccountBar.swift")
        XCTAssertFalse(bar.contains("Menu {"), "no quick menu on the gear")
        XCTAssertFalse(bar.contains(".menuStyle("), "no menu, so no menu chevron")
        XCTAssertFalse(bar.contains("profileTarget"), "Profile is reached through Settings, not the bar")
        XCTAssertTrue(bar.contains("Image(systemName: \"gearshape\")"))
        XCTAssertTrue(bar.contains("mac.sidebar.settings"), "the gear has its own identifier")
    }

    /// What the menu offered is still one click into Settings ▸ Account.
    func testSettingsAccountStillOffersProfileAndSignOut_ADEV78() throws {
        let account = try source("Astrid Mac/Views/MacAccountView.swift")
        XCTAssertTrue(account.contains("macOpensProfile(MacProfileLink.ownUserId"), "your profile, from your photo")
        XCTAssertTrue(account.contains("\"sign_out\""), "Sign Out")
    }
}
#endif
