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

    /// Waits for `element` to become (or stop being) reachable — what each step of the tour
    /// actually waits for. Best-effort: a tour screenshot is still useful when it is late.
    @MainActor
    @discardableResult
    private func waitUntil(_ element: XCUIElement, hittable: Bool = true, timeout: TimeInterval = 10) -> Bool {
        let format = hittable ? "exists == true AND isHittable == true" : "exists == false OR isHittable == false"
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter().wait(for: [reached], timeout: timeout) == .completed
    }

    @MainActor
    private func shot(_ name: String, of app: XCUIApplication) {
        // Querying the app waits for it to be idle — animations included — which is what the
        // one-second sleep that used to be here was guessing at (AITD-526).
        _ = app.windows.firstMatch.frame
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let out {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name).png"))
        }
    }

    /// The sidebar button sits in the floating header's top-left corner. Open once its header
    /// search can be reached — the closed sidebar keeps its elements in the tree.
    @MainActor
    private func openSidebar(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.11)).tap()
        waitUntil(app.buttons["sidebar.headerSearch"].firstMatch)
    }

    /// The one of several same-named buttons that is on screen (the hidden sidebar keeps its own).
    @MainActor
    private func visibleButton(_ app: XCUIApplication, _ id: String) -> XCUIElement? {
        app.buttons.matching(identifier: id).allElementsBoundByIndex.first { $0.isHittable }
    }

    @MainActor
    func testTour() throws {
        let app = UITestLaunch.makeApp()
        // English is already `makeApp`'s (AITD-526), so the fixture names below read the same as
        // Android's tour whatever the simulator is set to.
        app.launch()
        // Fixture TITLES are test data, not app copy, so matching them is not matching a string
        // the app translates.
        let fixture = app.staticTexts["UITEST Fixture — open task 2"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 20))
        shot("01-my-tasks", of: app)

        fixture.tap()
        XCTAssertTrue(UITestLaunch.waitForTaskDetail(app))
        shot("04-detail", of: app)
        app.swipeUp()
        shot("04b-detail-scrolled", of: app)
        app.swipeDown()
        UITestLaunch.swipeBackFromLeftEdge(app)
        UITestLaunch.waitForDisappearance(UITestLaunch.taskDetailHeader(app))

        openSidebar(app)
        shot("02-sidebar", of: app)
        // The sidebar's entry, not a task row's list chip with the same name.
        let list = app.staticTexts.matching(NSPredicate(format: "label == 'UI Test List' AND identifier != 'taskRow'")).firstMatch
        if list.exists {
            list.tap()
            // Picking a list closes the sidebar.
            waitUntil(app.buttons["sidebar.headerSearch"].firstMatch, hittable: false)
        }
        shot("03-list-or-board", of: app)
        if let listSettings = visibleButton(app, "listSettingsButton") {
            listSettings.tap()
            // The sheet covers the button that opened it.
            waitUntil(listSettings, hittable: false)
            shot("08-list-settings", of: app)
            app.swipeDown(velocity: .fast)
            waitUntil(listSettings)
        }

        openSidebar(app)
        if let search = visibleButton(app, "sidebar.headerSearch") {
            search.tap()
            waitUntil(search, hittable: false)
            shot("05-search", of: app)
        }

        openSidebar(app)
        if let settings = visibleButton(app, "sidebar.settings") {
            settings.tap()
            waitUntil(app.descendants(matching: .any).matching(identifier: "settings.profile").firstMatch)
            shot("06-settings", of: app)
            app.swipeUp()
            shot("06b-settings-scrolled", of: app)
        }
    }
}
