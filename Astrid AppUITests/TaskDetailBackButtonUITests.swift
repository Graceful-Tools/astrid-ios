import XCTest

/// Regression coverage for the task-detail back chevron (top-left) — AITD-425.
///
/// The button rendered as a 17pt `chevron.left` with `.buttonStyle(.plain)` and no
/// `.contentShape`, so the hittable area was the glyph itself, roughly 11×17pt — well under
/// Apple's 44pt HIG minimum. Its neighbour at the other end of the same header, the "..."
/// actions menu, had this exact defect fixed in 23da286; the chevron was left alone and kept
/// swallowing taps.
///
/// Reported as an iPad bug because that is where a missed tap has no fallback: on iPhone the
/// detail is pushed and `.enableInteractivePopGesture()` restores swipe-back, while on iPad it
/// is a side panel whose only other exit is a 20pt rightward drag.
///
/// Mirrors `TaskDetailActionsMenuUITests`, deliberately — one header, one shape of test.
final class TaskDetailBackButtonUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testBackButtonIsHittableAndClosesTaskDetail() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        guard let firstTask = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw XCTSkip("No tasks found in list")
        }
        UITestLaunch.tapCenter(firstTask)

        guard UITestLaunch.waitForTaskDetail(app) else { throw XCTSkip("Task detail did not appear") }

        let back = app.buttons[TaskDetailHeaderIdentifiers.back]
        XCTAssertTrue(back.waitForExistence(timeout: 3),
                      "the back control should expose its accessibility identifier")
        XCTAssertTrue(back.isHittable,
                      "the back control must be hittable — the tap area was the bare glyph before AITD-425")

        let frame = back.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44,
                                    "back width must meet the HIG 44pt minimum (got \(frame.width))")
        XCTAssertGreaterThanOrEqual(frame.height, 44,
                                    "back height must meet the HIG 44pt minimum (got \(frame.height))")

        // The point of the button, not just its size: on iPad this clears the container's
        // selectedTask; on iPhone it pops the stack. Either way the detail goes away.
        back.tap()
        let header = app.buttons[TaskDetailHeaderIdentifiers.header]
        XCTAssertTrue(header.waitForNonExistence(timeout: 5),
                      "tapping back must close the task detail")
    }
}

/// The app target's `TaskDetailHeader` is not linked into the UI test bundle — UI tests drive
/// the app from outside the process — so the identifiers it owns are repeated here. Keep the
/// two in step; `TaskDetailHeaderTests` pins the app-side values.
enum TaskDetailHeaderIdentifiers {
    static let header = "taskDetail.header"
    static let back = "taskDetail.back"
}
