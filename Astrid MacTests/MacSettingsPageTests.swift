//  MacSettingsPageTests.swift
//  ADEV-395: "[mac] Project Settings design is horrible … Doesn't respond to font size change,
//  width of the modal is wrong. Use the same design guidelines we use for the list Settings …
//  Let's adapt the web overall settings as a design standard and then apply it to list settings,
//  project settings, etc."

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacSettingsPageTests: XCTestCase {

    /// One size for every settings window: Project Settings opened at a fixed 380pt minimum while
    /// List Settings sized itself to the screen.
    func testADEV395_projectSettingsIsSizedLikeListSettings() {
        for screen in [CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900), CGSize(width: 2560, height: 1440)] {
            XCTAssertEqual(MacSettingsLayout.windowSize(screen: screen),
                           MacListChrome.settingsPopoverSize(screen: screen))
        }
        XCTAssertGreaterThan(MacSettingsLayout.windowSize(screen: CGSize(width: 1280, height: 800)).width, 380,
                             "wider than the old 380pt minimum")
    }

    /// Web's settings column (`max-w-2xl`, 42rem): readable, never the window's full width.
    func testADEV395_theColumnIsWebsReadableWidth() {
        XCTAssertEqual(MacSettingsLayout.columnMaxWidth, 672)
    }

    /// The page and its parts build, with text that the Mac text size reaches.
    @MainActor
    func testADEV395_thePageBuildsAtEveryTextSize() {
        for scale in MacTextSize.steps {
            let page = MacSettingsPage(systemImage: "folder", title: "Edit project", subtitle: "Astrid-Dev") {
                MacSettingsCard(systemImage: "pencil", title: "Details", description: "What it is") {
                    MacSettingsField(label: "Name", help: "Shown in the sidebar") { Text("Astrid-Dev") }
                }
            } actions: {
                Button("Save") {}
            }
            .environment(\.macTextScale, scale)
            let host = NSHostingView(rootView: page.frame(width: 640, height: 480))
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }

    func testADEV395_theNewLabelIsLocalized() {
        XCTAssertNotEqual(NSLocalizedString("projects.details", comment: ""), "projects.details")
    }
}
#endif
