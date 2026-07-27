//  MacUndoUITests.swift
//  Runtime check for Task 9b603be4 — ⌘Z must actually be live, not just modelled.
//
//  MacUndoTests covers the inverse math. What it cannot see is whether the window's UndoManager
//  ever reached MacUndoCoordinator: if `@Environment(\.undoManager)` were nil, every `record`
//  would be a silent no-op and Edit ▸ Undo would stay greyed out. The Edit menu is the observable
//  proof — it shows "Undo <action name>" only when an undo action is actually registered.
//  Hermetic: offline mode, so nothing touches a real account.

import XCTest

final class MacUndoUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCompletingATaskArmsEditUndo() {
        let app = XCUIApplication()
        // -uiTestSelectRow selects a rendered row; XCUITest cannot click macOS List rows, and the
        // Complete command is disabled without a selection.
        app.launchArguments += ["-uiTesting", "-uiTestSelectRow=0"]
        app.launch()

        // The offline choice persists in the shared container, so a second run may launch
        // straight into the shell — take whichever of the two screens shows up.
        let offline = app.descendants(matching: .any).matching(identifier: "login.offline").firstMatch
        let myTasks = app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline && !myTasks.exists {
            if offline.exists { offline.click() }
            _ = myTasks.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(myTasks.exists, "Should reach the shell")

        // A real list, so quick-add is available.
        let listName = "UITest Undo \(Int.random(in: 1000...9999))"
        app.descendants(matching: .any).matching(identifier: "sidebar.newList").firstMatch.click()
        let nameField = app.descendants(matching: .any).matching(identifier: "listEdit.name").firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click(); nameField.typeText(listName)
        app.buttons["Create"].firstMatch.click()

        let sidebarSearch = app.searchFields.firstMatch
        if sidebarSearch.waitForExistence(timeout: 5) { sidebarSearch.click(); sidebarSearch.typeText(listName) }
        let listRow = app.staticTexts[listName].firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 10)); listRow.click()

        app.activate()
        let quickAdd = app.descendants(matching: .any).matching(identifier: "tasks.quickAdd").firstMatch
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 10))
        quickAdd.click(); quickAdd.typeText("Undo me\n")
        XCTAssertTrue(app.staticTexts["Undo me"].firstMatch.waitForExistence(timeout: 10))

        // Before anything is undoable the item reads plain "Undo" and is disabled.
        XCTAssertFalse(undoMenuItemTitle(app).hasPrefix("Undo Complete"),
                       "Nothing should be undoable before the first change")

        // Complete via the menu (Task ▸ Complete, ⌘⏎) — the same path the shortcut takes.
        let taskMenu = app.menuBars.menuBarItems["Task"]
        XCTAssertTrue(taskMenu.waitForExistence(timeout: 10), "The Task menu should exist")
        // The row is selected by the launch hook as soon as the rows settle; the menu's enabled
        // state follows one state mirror later, so re-open until it catches up.
        var enabled = false
        for _ in 0..<10 where !enabled {
            taskMenu.click()
            let item = app.menuItems["Complete"].firstMatch
            enabled = item.waitForExistence(timeout: 2) && item.isEnabled
            if enabled { item.click() } else { app.typeKey(.escape, modifierFlags: []) }
        }
        if !enabled {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = "no-selection"; shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(enabled, "Complete needs a selected row (-uiTestSelectRow=0)")

        // End editing in the quick-add field first: while a text field is first responder its
        // FIELD EDITOR owns ⌘Z (standard macOS behaviour, and the menu title says so), so the
        // task stack only gets the keystroke once the field is done.
        app.staticTexts[listName].firstMatch.click()
        app.typeKey(.escape, modifierFlags: [])

        let title = undoMenuItemTitle(app)
        XCTAssertTrue(title.hasPrefix("Undo ") && title.count > "Undo ".count,
                      "Edit ▸ Undo should name the completion, got “\(title)” — nothing reached "
                      + "MacUndoCoordinator (task 9b603be4)")

        // …and taking it actually reverses the completion — the row's checkbox is the state,
        // not the menu label.
        let done = app.buttons["Completed, mark incomplete"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The task should now read as completed")
        let editMenu = app.menuBars.menuBarItems["Edit"]
        editMenu.click()
        editMenu.menus.firstMatch.menuItems.element(boundBy: 0).click()
        XCTAssertTrue(app.buttons["Not completed, mark complete"].firstMatch.waitForExistence(timeout: 10),
                      "⌘Z must un-complete the task, not just re-label the menu (task 9b603be4)")
    }

    /// Title of the first item in the Edit menu (AppKit's Undo item), with the menu closed again.
    @MainActor private func undoMenuItemTitle(_ app: XCUIApplication) -> String {
        let editMenu = app.menuBars.menuBarItems["Edit"]
        guard editMenu.waitForExistence(timeout: 10) else { return "" }
        editMenu.click()
        // Scope to the Edit menu's OWN menu — app.menuItems is app-wide and its first element is
        // the Apple menu's "About This Mac".
        let undo = editMenu.menus.firstMatch.menuItems.element(boundBy: 0)
        let title = undo.waitForExistence(timeout: 3) ? undo.title : ""
        app.typeKey(.escape, modifierFlags: [])
        return title
    }
}
