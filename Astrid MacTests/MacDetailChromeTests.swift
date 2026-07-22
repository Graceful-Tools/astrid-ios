//  MacDetailChromeTests.swift
//  Astrid for Mac — task-details surface is white, except Dark theme (readability).

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacDetailChromeTests: XCTestCase {

    func testWhiteInLightAndOceanDarkSurfaceInDark() {
        let key = "themeMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        for mode in ["ocean", "light"] {
            UserDefaults.standard.set(mode, forKey: key)
            XCTAssertEqual(MacDetailChrome.background, Color.white, "\(mode) details should be white")
        }
        UserDefaults.standard.set("dark", forKey: key)
        XCTAssertEqual(MacDetailChrome.background, Theme.Dark.bgSecondary, "Dark details use the dark surface")
        XCTAssertNotEqual(MacDetailChrome.background, Color.white)
    }
}
#endif
