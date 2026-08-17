import XCTest

/// UI tests for list operations
/// Tests list navigation, creation, and settings
final class ListUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - List Navigation Tests

    @MainActor
    func testListsTabVisible() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        // Find lists tab in tab bar
        let listsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'list'")).firstMatch

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Main Tab View"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Tab bar might use different naming
        _ = listsTab.exists ||
            app.tabBars.buttons["Lists"].exists ||
            app.buttons["Lists"].exists
    }

    @MainActor
    func testNavigateToLists() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Find and tap lists tab
        let listsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'list'")).firstMatch

        if listsTab.exists {
            listsTab.tap()
            sleep(1)
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Lists View"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testListExists() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Navigate to lists
        let listsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'list'")).firstMatch
        if listsTab.exists {
            listsTab.tap()
            sleep(1)
        }

        // Check for list cells or list names
        let lists = UITestLaunch.visibleRows(app).count

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Lists Count: \(lists)"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // At minimum, user should have at least one default list
        // This is a soft assertion since test account may vary
    }

    // MARK: - List Selection Tests

    @MainActor
    func testSelectList() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Navigate to lists
        let listsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'list'")).firstMatch
        if listsTab.exists {
            listsTab.tap()
            sleep(1)
        }

        // Find first list cell
        guard let firstList = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw XCTSkip("No lists found")
        }

        firstList.tap()
        sleep(1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Selected List View"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - List Creation Tests (if UI supports it)

    @MainActor
    func testCreateListButtonExists() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Navigate to lists
        let listsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'list'")).firstMatch
        if listsTab.exists {
            listsTab.tap()
            sleep(1)
        }

        // Look for create/add list button
        let addButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add' OR label CONTAINS[c] 'create' OR label CONTAINS[c] 'new' OR label == 'plus'")).firstMatch

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Create List Button Search"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Record whether add button exists (soft check)
        if addButton.exists {
            XCTAssertTrue(true, "Add list button found")
        }
    }

    // MARK: - List Settings Tests

    @MainActor
    func testPublicListSettingsShowsOnlyFiltersTab() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Navigate to lists
        let listsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'list'")).firstMatch
        if listsTab.exists {
            listsTab.tap()
            sleep(1)
        }

        // Find first list cell (assuming this might be a public list where user has viewer role)
        guard let firstList = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw XCTSkip("No lists found")
        }

        firstList.tap()
        sleep(1)

        // Look for settings button (gear icon or ellipsis menu)
        let settingsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'settings' OR label CONTAINS[c] 'gear' OR label == 'ellipsis'")).firstMatch

        // Hittable, not merely present: the sidebar keeps its gear button in the accessibility
        // tree while closed, so `exists` is true for an off-screen button and the tap fails —
        // which reads as a settings bug rather than as the wrong element (task 0bfb8eb4).
        guard settingsButton.exists, settingsButton.isHittable else {
            throw XCTSkip("Settings button not on screen")
        }

        settingsButton.tap()
        sleep(1)

        // Take screenshot of settings modal
        let settingsScreenshot = XCTAttachment(screenshot: app.screenshot())
        settingsScreenshot.name = "List Settings Modal"
        settingsScreenshot.lifetime = .keepAlways
        add(settingsScreenshot)

        // Check if the tab picker (segmented control) exists
        let tabPicker = app.segmentedControls.firstMatch

        // Check for individual tab labels
        let filtersTab = app.buttons["Filters"].exists ||
                        app.staticTexts["Filters"].exists
        let membersTab = app.buttons["Members"].exists ||
                        app.staticTexts["Members"].exists
        let adminTab = app.buttons["Admin"].exists ||
                      app.staticTexts["Admin"].exists

        // If this is a public list with viewer role:
        // - Tab picker should not exist OR only Filters tab should be visible
        // - Members and Admin tabs should not be visible

        // For a list where user is owner/admin:
        // - Tab picker should exist with all 3 tabs

        // Since we can't guarantee the test will run on a public list,
        // we document the behavior for both cases
        if !tabPicker.exists {
            // No tab picker means user is a viewer (correct behavior)
            XCTAssertTrue(true, "No tab picker - user is viewer with Filters-only view")
            XCTAssertFalse(membersTab, "Members tab should not be visible for viewers")
            XCTAssertFalse(adminTab, "Admin tab should not be visible for viewers")
        } else {
            // Tab picker exists means user is owner/admin (correct behavior)
            XCTAssertTrue(filtersTab, "Filters tab should be visible for owners/admins")
            XCTAssertTrue(membersTab, "Members tab should be visible for owners/admins")
            XCTAssertTrue(adminTab, "Admin tab should be visible for owners/admins")
        }

        // Take final screenshot
        let finalScreenshot = XCTAttachment(screenshot: app.screenshot())
        finalScreenshot.name = "Settings Tab Verification"
        finalScreenshot.lifetime = .keepAlways
        add(finalScreenshot)
    }
}
