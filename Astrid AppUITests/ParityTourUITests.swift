import XCTest

/// Screenshots of every main screen, signed in as the UI suite's account, to set beside Android's
/// (astrid-android `scripts/live-test.sh --tour`, same account and fixtures). Skips unless asked:
///
///     TEST_RUNNER_ASTRID_TOUR_OUT=/path/to/dir xcodebuild test -scheme "Astrid App" \
///       -only-testing:"Astrid AppUITests/ParityTourUITests" -destination '…'
///
/// Each shot is also attached to the test result.
final class ParityTourUITests: XCTestCase {
    private var out: String?

    override func setUpWithError() throws {
        out = ProcessInfo.processInfo.environment["ASTRID_TOUR_OUT"]
        try XCTSkipIf(out == nil, "set TEST_RUNNER_ASTRID_TOUR_OUT to take the tour")
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let out {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name).png"))
        }
    }

    /// The sidebar button sits in the floating header's top-left corner.
    private func openSidebar(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.11)).tap()
        sleep(2)
    }

    /// The one of several same-named buttons that is on screen (the hidden sidebar keeps its own).
    private func visibleButton(_ app: XCUIApplication, _ id: String) -> XCUIElement? {
        app.buttons.matching(identifier: id).allElementsBoundByIndex.first { $0.isHittable }
    }

    @MainActor
    func testTour() throws {
        let app = UITestLaunch.makeApp()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["UITEST Fixture — open task 2"].waitForExistence(timeout: 20))
        shot("01-my-tasks")

        app.staticTexts["UITEST Fixture — open task 2"].tap()
        sleep(2)
        shot("04-detail")
        app.swipeUp()
        shot("04b-detail-scrolled")
        app.swipeDown()
        UITestLaunch.swipeBackFromLeftEdge(app)
        sleep(2)

        openSidebar(app)
        shot("02-sidebar")
        // The sidebar's entry, not a task row's list chip with the same name.
        let list = app.staticTexts.matching(NSPredicate(format: "label == 'UI Test List' AND identifier != 'taskRow'")).firstMatch
        if list.exists {
            list.tap()
            sleep(3)
        }
        shot("03-list-or-board")
        if let listSettings = visibleButton(app, "gearshape") {
            listSettings.tap()
            sleep(2)
            shot("08-list-settings")
            app.swipeDown(velocity: .fast)
            sleep(1)
        }

        openSidebar(app)
        if let search = visibleButton(app, "magnifyingglass") {
            search.tap()
            sleep(2)
            shot("05-search")
        }

        openSidebar(app)
        if let settings = visibleButton(app, "gearshape") {
            settings.tap()
            sleep(2)
            shot("06-settings")
            app.swipeUp()
            shot("06b-settings-scrolled")
        }
    }
}
