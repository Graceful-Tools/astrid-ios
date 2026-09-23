import XCTest
@testable import Astrid_App

/// Tests for the task-detail header's back control (AITD-425).
///
/// Two things are pinned here, because the bug needed both.
///
/// **The tap target.** The back chevron rendered as a 17pt `chevron.left` with
/// `.buttonStyle(.plain)` and no `.contentShape`, so the hittable area was the glyph itself —
/// roughly 11×17pt, well under Apple's 44pt HIG minimum. Its neighbour in the same HStack, the
/// "..." actions menu, had exactly this defect fixed in 23da286 and got a 44×44 frame; the
/// chevron three views to its left was left alone.
///
/// It read as an iPad-only bug because of what happens when a tap MISSES. On iPhone the detail
/// is pushed onto a navigation stack and `.enableInteractivePopGesture()` restores swipe-back,
/// so a missed tap is rescued by a gesture people already use. On iPad the detail is a side
/// panel — the only other way out is the panel's own 20pt rightward drag — so a missed tap is
/// simply nothing happening, which is what got reported.
///
/// **The action.** Which of the two things back does is now named rather than inferred from
/// reading the call sites, following `UserProfileView.backAction(isRootDestination:)`:
///  - PANEL (iPad): `iPadTaskManagerView` supplies `onClose`, which clears `selectedTask`.
///    `dismiss()` would be a no-op here — the detail is the root of its own NavigationStack,
///    so there is nothing to pop.
///  - PUSHED (iPhone, and task references opened inside the stack): no `onClose`, so back
///    pops the stack.
final class TaskDetailHeaderTests: XCTestCase {

    // MARK: - The tap target

    func testBackButtonMeetsHIGMinimumTapTarget() {
        XCTAssertGreaterThanOrEqual(
            TaskDetailHeader.minimumTapTarget, 44,
            "the back chevron's hit area was the 17pt glyph (~11×17pt); Apple's HIG minimum is 44pt")
    }

    // MARK: - The action

    func testPanelBackClosesThePanel() {
        XCTAssertEqual(
            TaskDetailHeader.backAction(hasPanelClose: true), .closePanel,
            "the iPad side panel is the root of its own NavigationStack — dismiss() has nothing to pop, so back must clear selectedTask")
    }

    func testPushedBackDismissesTheStack() {
        XCTAssertEqual(
            TaskDetailHeader.backAction(hasPanelClose: false), .dismissStack,
            "a detail pushed from a list row or a task reference must pop the stack")
    }

    // MARK: - Identifiers

    func testBackButtonHasAStableIdentifier() {
        XCTAssertEqual(
            TaskDetailHeader.backAccessibilityIdentifier, "taskDetail.back",
            "the UI suite targets the back control by identifier, which does not change when the app is in French")
        XCTAssertNotEqual(
            TaskDetailHeader.backAccessibilityIdentifier, TaskDetailHeader.accessibilityIdentifier,
            "the back control and the header title are different elements and must not share an identifier")
    }
}
