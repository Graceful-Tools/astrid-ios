import XCTest

/// The user journeys, end to end through the real server (AITD-528).
///
/// Views are barely covered by unit tests, so these are what stands between a broken screen and a
/// user. Each journey drives the app the way a person would and then asks the SERVER — through
/// `UITestAPI`, with the run's own session — whether the change persisted. A row that shows a tick
/// proves the app drew one; only the server can say the write went through `TaskService`, the
/// Outbox and the core.
///
/// Every journey owns its fixture, so they can run in any order and alongside the other suites:
///
/// | Journey | Fixture |
/// |---|---|
/// | 2 quick add, 8 new list | creates its own |
/// | 3 complete / un-complete | `noList` |
/// | 4 repeating rollover | `dailyRepeating` |
/// | 5 edit title and description | `dueToday` |
/// | 7 comment | `withComment` |
/// | 9 permissions | `lists.shared` (viewer), `lists.main` (owner) |
/// | 10 board status | `boardInbox` |
/// | 11 offline Outbox | creates its own |
/// | 12 search, sign out | classic "open task 3" |
///
/// Journeys 1 and 6 live with the tests they extend: `SignedInPreconditionUITests` and
/// `TaskDueDateClearUITests`.
///
/// They need a per-run account (`npm run test:ui` mints one): the shared account has no fixture
/// ids, so there is nothing to ask the server about. That is the only skip.
///
/// No fixed sleeps: every wait polls for the thing it is waiting for, on screen or on the server.
final class E2EJourneyUITests: XCTestCase {

    private var app: XCUIApplication!
    private var fixtures: UITestFixtures!

    /// Short and unique per test, so a title names exactly one task even across reruns.
    private let tag = String(UUID().uuidString.prefix(6))

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let fixtures = UITestLaunch.fixtures else {
            throw XCTSkip("The journeys need a per-run account — run `npm run test:ui`, which mints one.")
        }
        self.fixtures = fixtures
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - 2. Quick add

    /// Quick add in a list → the row appears → the server has it, on that list.
    @MainActor
    func test02_QuickAddLandsOnTheListOnTheServer() throws {
        try launchSignedIn()
        try openList(fixtures.lists.main.id)
        let title = "T-\(fixtures.runId)-add-\(tag)"
        try quickAdd(title)

        let main = fixtures.lists.main.id
        try UITestAPI.waitForTask(titled: title, "the quick-added task on its list") {
            $0.listIds.contains(main) && !$0.completed
        }
    }

    // MARK: - 3. Complete and un-complete

    /// The detail's checkbox completes the task, and tapping it again reopens it — both on the
    /// server, not just on screen.
    @MainActor
    func test03_CompleteThenUncompleteReachesTheServer() throws {
        let fixture = try named("noList")
        try launchSignedIn()
        try openTask(titled: fixture.title)

        let control = try element("taskDetail.leadingControl")
        UITestLaunch.tapCenter(control)
        try waitFor("the checkbox to show checked") { control.label.contains("_checked") }
        try UITestAPI.waitForTask(id: fixture.id, "completed == true") { $0.completed }

        UITestLaunch.tapCenter(control)
        try waitFor("the checkbox to clear") { !control.label.contains("_checked") }
        try UITestAPI.waitForTask(id: fixture.id, "completed == false") { !$0.completed }
    }

    // MARK: - 4. Repeating rollover

    /// Ticking a daily task does not finish it: it stays open and its due date moves on a day.
    ///
    /// The end-to-end guard for `TaskService.completeTask` → astrid-core's rollover (ASTRID.md
    /// §0 rules 2–4). A completion that went through `updateTask(completed: true)` instead would
    /// leave the series closed on the server, which is the regression users notice.
    @MainActor
    func test04_CompletingADailyTaskRollsItForwardADay() throws {
        let fixture = try named("dailyRepeating")
        let seededDue = try XCTUnwrap(fixture.dueDateTime.flatMap(Self.date),
                                      "the seeder gives the repeating fixture a due date")
        try launchSignedIn()

        guard let title = UITestLaunch.waitForCreatedTask(app, titled: fixture.title, timeout: 15) else {
            throw UITestFailure("The daily-repeating fixture is not on My Tasks")
        }
        let row = app.cells.containing(NSPredicate(format: "label == %@", title.label)).firstMatch
        let checkbox = row.buttons.matching(identifier: UITestLaunch.taskRowIdentifier).firstMatch
        XCTAssertTrue(checkbox.exists, "the row has a checkbox")
        UITestLaunch.tapCenter(checkbox)

        let next = seededDue.addingTimeInterval(24 * 60 * 60)
        let rolled = try UITestAPI.waitForTask(id: fixture.id, "the due date one day on") {
            !$0.completed && $0.dueDateTime.flatMap(Self.date) == next
        }
        XCTAssertEqual(rolled.repeating, "daily", "the series is still daily")

        // And the row is still there, open: a repeating task is not done when one occurrence is.
        XCTAssertTrue(UITestLaunch.waitForCreatedTask(app, titled: fixture.title, timeout: 10) != nil,
                      "the repeating task stays on the list")
        let reread = row.buttons.matching(identifier: UITestLaunch.taskRowIdentifier).firstMatch
        XCTAssertFalse(reread.label.contains("_checked"), "its checkbox is clear again")
    }

    // MARK: - 5. Edit title and description

    /// Edits made in the detail survive leaving it, coming back, and the server.
    @MainActor
    func test05_EditedTitleAndDescriptionPersist() throws {
        let fixture = try named("dueToday")
        try launchSignedIn()
        try openTask(titled: fixture.title)

        let newTitle = "\(fixture.title) edited \(tag)"
        let titleField = try element("taskDetail.title")
        titleField.tap()
        try waitFor("the keyboard for the title") { self.app.keyboards.count > 0 }
        // Replace the whole title: where a tap leaves the caret depends on how the title wraps.
        // Select-all can land before the field has settled its focus, and then the new title is
        // typed into the middle of the old one — so check, and select again if it did.
        for _ in 0..<3 where (titleField.value as? String) != newTitle {
            titleField.typeKey("a", modifierFlags: .command)
            titleField.typeText(newTitle)
        }
        XCTAssertEqual(titleField.value as? String, newTitle, "the title field holds the new title")
        titleField.typeText("\n")

        let description = "Description \(tag)"
        let display = try element("taskDetail.description")
        UITestLaunch.tapCenter(display)
        let editor = app.textViews.matching(identifier: "taskDetail.description").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "tapping the description opens its editor")
        try waitFor("the keyboard for the description") { self.app.keyboards.count > 0 }
        editor.typeText(description)
        // The keyboard's Done ends the edit, which is what saves it.
        let done = app.toolbars.buttons.element(boundBy: app.toolbars.buttons.count - 1)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the description keyboard offers Done")
        done.tap()

        try UITestAPI.waitForTask(id: fixture.id, "the new title and description") {
            $0.title == newTitle && $0.description == description
        }

        // Leave and come back: the detail reads what was saved, not what was typed.
        try element("taskDetail.back").tap()
        try openTask(titled: newTitle)
        let reopened = try element("taskDetail.title")
        try waitFor("the reopened title to be the new one") { (reopened.value as? String) == newTitle }
        let text = app.staticTexts.matching(NSPredicate(format: "label == %@", description)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the reopened detail shows the new description")
    }

    // MARK: - 7. Comment

    /// A sent comment shows in the thread and reaches the server.
    @MainActor
    func test07_ASentCommentReachesTheServer() throws {
        let fixture = try named("withComment")
        let before = try UITestAPI.comments(taskId: fixture.id).count
        try launchSignedIn()
        try openTask(titled: fixture.title)

        let field = UITestLaunch.commentField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the detail has a comment box")
        field.tap()
        try waitFor("the keyboard for the comment") { self.app.keyboards.count > 0 }
        let text = "Comment \(tag)"
        field.typeText(text)
        let send = app.buttons
            .matching(NSPredicate(format: "identifier CONTAINS 'paperplane' OR label CONTAINS[c] 'Send'"))
            .firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "a typed comment can be sent")
        UITestLaunch.tapCenter(send)

        let bubble = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "the comment appears in the thread")
        try waitForServer("the comment on the task") {
            let comments = try UITestAPI.comments(taskId: fixture.id)
            return comments.count == before + 1
                && comments.contains { ($0["content"] as? String) == text }
        }
    }

    // MARK: - 8. Create a list

    /// A new list appears in the sidebar and on the server, and a task added to it lands on it.
    @MainActor
    func test08_ANewListTakesATask() throws {
        try launchSignedIn()
        try openSidebar()
        try element("sidebar.addList").tap()

        let name = "L-\(fixtures.runId)-\(tag)"
        let field = try element("listEdit.name")
        field.tap()
        field.typeText(name)
        try element("listEdit.save").tap()

        let list = try UITestAPI.waitForList(named: name)
        // Opening it from the sidebar is the proof it appeared there.
        try openList(list.id)
        let title = "T-\(fixtures.runId)-inlist-\(tag)"
        try quickAdd(title)
        try UITestAPI.waitForTask(titled: title, "the task on the new list") { $0.listIds.contains(list.id) }
    }

    // MARK: - 9. Permissions

    /// A viewer cannot manage a list's settings; its owner can (`ListPermissions.canEditSettings`,
    /// the matrix in astrid-web `docs/PRODUCT_CONTRACT.md`).
    ///
    /// The tabs are found by their icons, which are the same in every language. Today a viewer
    /// gets no settings gear at all — the header offers it only to an explicit member or better
    /// (`TaskListView.canShowListSettings`, the core's `has_explicit_list_role`). Whether a viewer
    /// should get a Filters-only sheet instead is a product question, so this pins the part the
    /// matrix decides: a viewer has no way to the Admin tab.
    @MainActor
    func test09_AViewerGetsNoAdminTabAndTheOwnerDoes() throws {
        let shared = try XCTUnwrap(fixtures.lists.shared, "the run seeds a list it can only view")
        let lists = try UITestAPI.lists(userId: fixtures.user?.id)
        XCTAssertEqual(lists.first { $0.id == shared.id }?.memberRole, "viewer",
                       "the server has this user as a viewer of the shared list")
        if let user = fixtures.user?.id {
            XCTAssertEqual(lists.first { $0.id == fixtures.lists.main.id }?.ownerId, user,
                           "and as the owner of its own list")
        }

        try launchSignedIn()
        try openList(shared.id)
        let viewerTask = try XCTUnwrap(fixtures.tasks["shared"], "the run seeds a task on the shared list")
        XCTAssertTrue(UITestLaunch.waitForCreatedTask(app, titled: viewerTask.title, timeout: 15) != nil,
                      "a viewer can see the shared list's tasks")
        if let gear = try? element("listSettingsButton", timeout: 2) {
            gear.tap()
            XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(segment("gearshape").exists, "a viewer must not get the Admin tab")
            try element("listSettings.done").tap()
        }

        try openList(fixtures.lists.main.id)
        try openListSettings()
        XCTAssertTrue(segment("line.3.horizontal.decrease.circle").exists, "the owner sees Filters")
        XCTAssertTrue(segment("person.2").exists, "the owner sees Members")
        XCTAssertTrue(segment("gearshape").exists, "the owner gets the Admin tab")
        try element("listSettings.done").tap()
    }

    // MARK: - 10. Board

    /// A project-backed list opens as a board, and a card's status changes through the quick
    /// changer — not drag and drop, which XCUITest cannot drive reliably (see BoardViewUITests).
    @MainActor
    func test10_TheQuickChangerMovesACardOnTheBoard() throws {
        let board = try XCTUnwrap(fixtures.lists.board, "the run seeds a board")
        let card = try named("boardInbox")
        try launchSignedIn()
        try openList(board.id)

        let inbox = app.staticTexts.matching(identifier: "board.column.__virtual_inbox__").firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 15), "the board shows its Inbox column")
        let title = app.staticTexts.matching(NSPredicate(format: "label == %@", card.title)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the inbox card is on the board")

        // The card's leading control: the `taskRow` button level with its title.
        let control = app.buttons.matching(identifier: UITestLaunch.taskRowIdentifier).allElementsBoundByIndex
            .first { abs($0.frame.midY - title.frame.midY) < 30 && $0.frame.maxX <= title.frame.minX }
        let leading = try XCTUnwrap(control, "the card has a leading control beside its title")
        UITestLaunch.tapCenter(leading)

        let doing = try element("projectState.doing")
        doing.tap()
        try UITestAPI.waitForTask(id: card.id, "statusRole == doing") { $0.statusRole == "doing" }
    }

    // MARK: - 11. Offline Outbox

    /// A task added with no network is delivered when the app comes back online.
    ///
    /// Three launches on one named scratch cache: online, to fill it; offline (every request
    /// refused, `-uiTestOffline`), to quick-add into the journal; online again, to deliver it.
    @MainActor
    func test11_ATaskAddedOfflineIsDeliveredOnRelaunch() throws {
        let cache = "outbox-\(tag)"
        let title = "T-\(fixtures.runId)-offline-\(tag)"
        let main = fixtures.lists.main.id

        app = UITestLaunch.makeApp(cacheName: cache)
        try launchSignedIn()
        app.terminate()

        app = UITestLaunch.makeApp(cacheName: cache, offline: true)
        try launchSignedIn()
        try openList(main)
        try quickAdd(title)
        XCTAssertFalse(try UITestAPI.allTasks().contains { $0.title == title },
                       "offline, the task must not have reached the server yet")
        app.terminate()

        app = UITestLaunch.makeApp(cacheName: cache)
        try launchSignedIn()
        try UITestAPI.waitForTask(titled: title, timeout: 45, "the offline task, delivered") {
            $0.listIds.contains(main)
        }
    }

    // MARK: - 12. Search, sign out

    /// Search finds a fixture by title; sign out returns to the welcome screen and stays there.
    ///
    /// "Relaunch → still signed out" is not checked: this harness hands the app its session on
    /// every launch, by design, so a relaunch signs in again whatever sign-out did. What CAN go
    /// wrong in-process is checked instead — the keychain still answers with the injected cookie
    /// after sign-out, so a background session refresh that ignored the sign-out would put the
    /// app straight back in.
    @MainActor
    func test12_SearchFindsAFixtureThenSignOutStaysSignedOut() throws {
        let fixture = try XCTUnwrap(fixtures.tasks.classic.first { $0.title.hasSuffix("open task 3") },
                                    "the seeder's third open task")
        XCTAssertTrue(try UITestAPI.task(id: fixture.id)?.title == fixture.title,
                      "the server has the task being searched for")
        try launchSignedIn()

        try openSidebar()
        try element("sidebar.headerSearch").tap()
        let field = try element("search.field")
        field.tap()
        field.typeText("open task 3")
        let result = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                                                          UITestLaunch.taskRowIdentifier, fixture.title))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "search finds the fixture")

        try openSidebar()
        try element("sidebar.settings").tap()
        let signOut = app.buttons["account.destructive.signOut"]
        var swipes = 0
        while !signOut.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(signOut.isHittable, "Settings offers Sign out")
        signOut.tap()
        try element("account.destructive.signOutConfirm").tap()

        let welcome = app.buttons["Use without account"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 15), "signing out shows the welcome screen")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            XCTAssertTrue(welcome.exists, "the app must not sign itself back in after sign-out")
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // MARK: - Steps

    @MainActor
    private func launchSignedIn() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        guard UITestLaunch.waitForFirstVisibleRow(app, timeout: 20) != nil else {
            throw UITestFailure("Signed in, but no task rows appeared — the seeder guarantees them")
        }
    }

    /// A named fixture this run was seeded with.
    private func named(_ key: String) throws -> UITestFixtures.TaskRef {
        guard let task = fixtures.tasks[key] else {
            throw UITestFailure("The run has no \"\(key)\" fixture — is astrid-web's seeder older than AITD-527?")
        }
        return task
    }

    /// The first element with this identifier that a person could tap, waiting for one.
    ///
    /// Hittable, not merely present: the closed sidebar keeps its rows in the tree, off screen.
    @MainActor
    private func element(_ identifier: String, timeout: TimeInterval = 10) throws -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return hit
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        attachScreenshot("No \(identifier)")
        throw UITestFailure("Nothing tappable with identifier \"\(identifier)\" within \(Int(timeout))s")
    }

    @MainActor
    private func waitFor(_ what: String, timeout: TimeInterval = 10,
                         _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        attachScreenshot("Timed out: \(what)")
        throw UITestFailure("Timed out after \(Int(timeout))s waiting for \(what)")
    }

    /// Kept on failure, so a red journey shows the screen it was looking at.
    @MainActor
    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitForServer(_ what: String, timeout: TimeInterval = 20,
                               _ condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try condition() { return }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        throw UITestFailure("Server never showed \(what) within \(Int(timeout))s")
    }

    /// The content sits at the left edge only while the sidebar is closed. The sidebar's own rows
    /// stay in the tree, and report hittable, wherever it is — so they cannot say.
    @MainActor
    private var contentIsShowing: Bool {
        app.buttons.matching(identifier: "taskList.menu").allElementsBoundByIndex
            .contains { $0.isHittable && $0.frame.minX < 40 }
    }

    /// Opens the sidebar, or leaves it open: tapping the menu while it is already out (after the
    /// add-list sheet, say) would close it, and the next tap would land on a task row.
    @MainActor
    private func openSidebar() throws {
        guard contentIsShowing else { return }
        try element("taskList.menu").tap()
        try waitFor("the sidebar to open") { !self.contentIsShowing }
    }

    /// Open a list from the sidebar, by id, and wait for the sidebar to close over it.
    @MainActor
    private func openList(_ listId: String) throws {
        try openSidebar()
        try element("sidebar.list.\(listId)").tap()
        try waitFor("the sidebar to close") { self.contentIsShowing }
    }

    @MainActor
    private func openListSettings() throws {
        try element("listSettingsButton").tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 10),
                      "list settings opens on its tabs")
    }

    @MainActor
    private func segment(_ icon: String) -> XCUIElement {
        app.segmentedControls.firstMatch.buttons.matching(identifier: icon).firstMatch
    }

    @MainActor
    private func quickAdd(_ title: String) throws {
        let field = UITestLaunch.quickAddField(app)
        guard field.waitForExistence(timeout: 10), UITestLaunch.focusQuickAdd(app) else {
            attachScreenshot("Quick add never took focus")
            throw UITestFailure("Quick add never took keyboard focus")
        }
        field.typeText(title + "\n")
        guard UITestLaunch.waitForCreatedTask(app, titled: title, timeout: 10) != nil else {
            throw UITestFailure("The quick-added \"\(title)\" never appeared in the list")
        }
    }

    /// Find a task's row on the current screen, scrolling to it, and open its detail.
    @MainActor
    private func openTask(titled title: String) throws {
        guard let row = UITestLaunch.waitForCreatedTask(app, titled: title, timeout: 15) else {
            throw UITestFailure("\"\(title)\" is not on screen")
        }
        UITestLaunch.tapCenter(row)
        guard UITestLaunch.waitForTaskDetail(app) else {
            throw UITestFailure("Tapping \"\(title)\" did not open its detail")
        }
    }

    /// The API's ISO-8601 dates carry milliseconds; the seeder's do too.
    private static func date(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}
