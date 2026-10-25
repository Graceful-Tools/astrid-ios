//  MacE2EJourneyUITests.swift
//  The Mac user journeys, end to end through the real server (AITD-529).
//
//  Until this file the Mac UI suite could not be signed in at all — `-uiTesting` forced the
//  sign-in screen — so Mac had no end-to-end coverage against the server. Each journey drives the
//  app the way a person would and then asks the SERVER, through `UITestAPI` with the run's own
//  session, whether the change persisted. A tick on a row proves the app drew one; only the server
//  can say the write went through `TaskService`, the Outbox and the core.
//
//  The fixtures are the iOS journeys' (`E2EJourneyUITests`), seeded per run by astrid-web's
//  `uitest-account.ts --run`, so each journey owns its own task:
//
//  | Journey | Fixture |
//  |---|---|
//  | 1 signed-in launch | `dueToday`, `lists.main` |
//  | 2 quick add | creates its own |
//  | 3 complete via Task ▸ Complete | `noList` |
//  | 4 repeating rollover | `dailyRepeating` |
//  | 5 edit the title | `dueToday` |
//  | 6 comment | `withComment` |
//
//  XCUITest cannot click a macOS List row, so a journey selects its fixture at launch with
//  `-uiTestSelectTask=<id>` and acts through the menu bar and the detail — the paths a keyboard
//  user takes. No fixed sleeps: every wait polls for what it is waiting for.

import XCTest

final class MacE2EJourneyUITests: XCTestCase {

    private var fixtures: UITestFixtures!

    /// Short and unique per test, so a title names exactly one task even across reruns.
    private let tag = String(UUID().uuidString.prefix(6))

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let fixtures = UITestSessionResource.fixtures else {
            throw XCTSkip("The journeys need a per-run account — run `npm run test:mac:ui`, which mints one.")
        }
        self.fixtures = fixtures
    }

    // MARK: - 1. Signed-in launch

    /// A run handed a session lands in the shell signed in, and the account's tasks and lists
    /// arrive from the server.
    @MainActor
    func test01_SignedInLaunchShowsTheAccountsFixtures() throws {
        let app = try launchSignedIn()
        XCTAssertFalse(app.buttons["login.passkey"].exists, "a run with a session is not on the sign-in screen")
        try openMyTasks(app)
        try waitForText(app, try named("dueToday").title, "the due-today fixture on My Tasks")
        try waitForText(app, fixtures.lists.main.name, "the run's main list in the sidebar")
    }

    // MARK: - 2. Quick add

    /// Quick add in a list → the row appears → the server has it, on that list.
    @MainActor
    func test02_QuickAddLandsOnTheListOnTheServer() throws {
        let app = try launchSignedIn()
        try openList(app, named: fixtures.lists.main.name)

        let title = "T-\(fixtures.runId)-add-\(tag)"
        let quickAdd = try element(app, "tasks.quickAdd")
        quickAdd.click()
        quickAdd.typeText(title + "\n")
        try waitForText(app, title, "the quick-added row")

        let main = fixtures.lists.main.id
        try UITestAPI.waitForTask(titled: title, "the quick-added task on its list") {
            $0.listIds.contains(main) && !$0.completed
        }
    }

    // MARK: - 3. Complete via the menu

    /// Task ▸ Complete on the selected row completes it on the server.
    @MainActor
    func test03_TaskMenuCompleteReachesTheServer() throws {
        let fixture = try named("noList")
        let app = try launchSignedIn(selecting: fixture.id)
        try openMyTasks(app)
        try waitForText(app, fixture.title, "the no-list fixture on My Tasks")

        try completeSelectedViaMenu(app)
        try UITestAPI.waitForTask(id: fixture.id, "completed == true") { $0.completed }
    }

    // MARK: - 4. Repeating rollover

    /// Completing a daily task does not finish it: it stays open and its due date moves a day.
    /// The end-to-end guard for `TaskService.completeTask` → astrid-core's rollover (ASTRID.md §0
    /// rules 2–4) on the Mac.
    @MainActor
    func test04_CompletingADailyTaskRollsItForwardADay() throws {
        let fixture = try named("dailyRepeating")
        let seededDue = try XCTUnwrap(fixture.dueDateTime.flatMap(Self.date),
                                      "the seeder gives the repeating fixture a due date")
        let app = try launchSignedIn(selecting: fixture.id)
        try openMyTasks(app)
        try waitForText(app, fixture.title, "the daily fixture on My Tasks")

        try completeSelectedViaMenu(app)
        let next = seededDue.addingTimeInterval(24 * 60 * 60)
        let rolled = try UITestAPI.waitForTask(id: fixture.id, "the due date one day on") {
            !$0.completed && $0.dueDateTime.flatMap(Self.date) == next
        }
        XCTAssertEqual(rolled.repeating, "daily", "the series is still daily")
    }

    // MARK: - 5. Edit the title

    /// A title edited in the detail reaches the server.
    @MainActor
    func test05_EditedTitleReachesTheServer() throws {
        let fixture = try named("dueToday")
        let app = try launchSignedIn(selecting: fixture.id)
        try openMyTasks(app)

        let titleField = try element(app, "taskDetail.title", timeout: 30)
        let newTitle = "\(fixture.title) edited \(tag)"
        titleField.click()
        titleField.typeKey("a", modifierFlags: .command)
        titleField.typeText(newTitle + "\n")

        try UITestAPI.waitForTask(id: fixture.id, "the edited title") { $0.title == newTitle }
    }

    // MARK: - 6. Comment

    /// A comment sent from the detail is on the server.
    @MainActor
    func test06_CommentSentFromTheDetailReachesTheServer() throws {
        let fixture = try named("withComment")
        let before = try UITestAPI.comments(taskId: fixture.id).count
        let app = try launchSignedIn(selecting: fixture.id)
        try openMyTasks(app)

        let text = "Mac journey comment \(tag)"
        let field = try element(app, "comment.input", timeout: 30)
        field.click()
        field.typeText(text)
        try element(app, "comment.send").click()

        let deadline = Date().addingTimeInterval(20)
        var comments: [[String: Any]] = []
        repeat {
            comments = try UITestAPI.comments(taskId: fixture.id)
            if comments.contains(where: { ($0["content"] as? String) == text }) { break }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        XCTAssertTrue(comments.contains { ($0["content"] as? String) == text },
                      "the server has the comment (had \(before), now \(comments.count))")
    }

    // MARK: - Helpers

    /// Launch with this run's session and wait for the shell. Signed out WITH a session is the
    /// app failing to sign in — a failure, never a skip (AITD-525).
    @MainActor
    private func launchSignedIn(selecting taskId: String? = nil) throws -> XCUIApplication {
        let args = taskId.map { ["-uiTestSelectTask=\($0)"] } ?? []
        let app = MacUITestLaunch.makeApp(arguments: args, signedIn: true)
        app.launch()
        let myTasks = app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline && !myTasks.exists {
            if app.buttons["login.passkey"].exists {
                attachScreenshot(app, "signed out with a session")
                throw UITestFailure("The app showed the sign-in screen although the run was handed a session")
            }
            _ = myTasks.waitForExistence(timeout: 2)
        }
        guard myTasks.exists else {
            attachScreenshot(app, "no shell")
            throw UITestFailure("The signed-in shell never appeared")
        }
        return app
    }

    @MainActor
    private func openMyTasks(_ app: XCUIApplication) throws {
        try element(app, "sidebar.myTasks").click()
    }

    @MainActor
    private func openList(_ app: XCUIApplication, named name: String) throws {
        try waitForText(app, name, "the list \"\(name)\" in the sidebar", timeout: 30)
        app.staticTexts[name].firstMatch.click()
        app.activate()
    }

    /// Task ▸ Complete, re-opening the menu until it is enabled: the launch hook selects the row
    /// as soon as the rows settle, and the menu's enabled state follows one state mirror later.
    @MainActor
    private func completeSelectedViaMenu(_ app: XCUIApplication) throws {
        let taskMenu = app.menuBars.menuBarItems["Task"]
        guard taskMenu.waitForExistence(timeout: 10) else { throw UITestFailure("No Task menu") }
        for _ in 0..<20 {
            taskMenu.click()
            let item = app.menuItems["Complete"].firstMatch
            if item.waitForExistence(timeout: 2), item.isEnabled {
                item.click()
                return
            }
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.5)
        }
        attachScreenshot(app, "Complete never enabled")
        throw UITestFailure("Task ▸ Complete never became enabled — the row was not selected")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String,
                         timeout: TimeInterval = 15) throws -> XCUIElement {
        let match = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        guard match.waitForExistence(timeout: timeout) else {
            attachScreenshot(app, "missing \(identifier)")
            throw UITestFailure("No element \"\(identifier)\" within \(Int(timeout))s")
        }
        return match
    }

    @MainActor
    private func waitForText(_ app: XCUIApplication, _ text: String, _ what: String,
                             timeout: TimeInterval = 30) throws {
        guard app.staticTexts[text].firstMatch.waitForExistence(timeout: timeout) else {
            attachScreenshot(app, "missing: \(what)")
            throw UITestFailure("Timed out after \(Int(timeout))s waiting for \(what)")
        }
    }

    private func named(_ key: String) throws -> UITestFixtures.TaskRef {
        guard let task = fixtures.tasks[key] else {
            throw UITestFailure("The run has no \"\(key)\" fixture — is astrid-web's seeder older than AITD-527?")
        }
        return task
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let window = app.windows.firstMatch
        let shot = XCTAttachment(screenshot: window.exists ? window.screenshot() : XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private static func date(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}
