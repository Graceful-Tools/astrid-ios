//  MacMenuCommandsUITests.swift
//  End-to-end check for Task e0412a64 — the View menu's commands must actually do something.
//  Unit tests pin the table; only the running app can show the items are wired to the shell.
//  Hermetic: offline mode.

import XCTest

final class MacMenuCommandsUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testViewMenuOffersAndPerformsTheWebsCommands() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()

        let offline = app.descendants(matching: .any).matching(identifier: "login.offline").firstMatch
        let myTasks = app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline && !myTasks.exists {
            if offline.exists { offline.click() }
            _ = myTasks.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(myTasks.exists, "Should reach the shell")

        app.activate()
        let viewMenu = app.menuBars.menuBarItems.matching(identifier: "View").firstMatch
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 10), "There should be a View menu")
        viewMenu.click()
        let items = viewMenu.menus.firstMatch.menuItems
        let titles = (0..<items.count).map { items.element(boundBy: $0).title }
        for title in ["Search", "List View", "Board View", "Chat View", "Filter tasks"] {
            XCTAssertTrue(titles.contains(title),
                          "View menu should offer “\(title)”; it has \(titles)")
        }

        // …and Search actually navigates, rather than being a decorative item.
        items["Search"].click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "search.field")
            .firstMatch.waitForExistence(timeout: 10),
                      "View ▸ Search should open the search surface (task e0412a64)")
    }
}
