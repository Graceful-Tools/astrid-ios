import XCTest
@testable import Astrid_App

/// Tests for `UserProfileView`'s back-button action selection.
///
/// `UserProfileView` is shown two ways:
///  - ROOT: via MainTabView / iPadTaskManagerView when `selectedListId == "profile"`
///    (opened from the sidebar / deep link). Going back must post `.closeProfile`
///    so the tab routing returns to "my-tasks".
///  - PUSHED: via `NavigationLink` / `navigationDestination` from task comments,
///    the task creator, list membership, and @mention references. Going back must
///    POP the navigation stack (`dismiss()`).
///
/// The bug: every instance posted `.closeProfile`, so backing out of a profile
/// pushed from comments tore down the whole NavigationStack instead of returning
/// to the task — the "can't get back to the task" stuck state.
final class UserProfileBackActionTests: XCTestCase {

    func testPushedProfileBackDismissesStack() {
        XCTAssertEqual(UserProfileView.backAction(isRootDestination: false), .dismiss,
                       "a profile pushed from comments/members must pop the stack, not reset tabs")
    }

    func testRootProfileBackPostsCloseProfile() {
        XCTAssertEqual(UserProfileView.backAction(isRootDestination: true), .postCloseProfile,
                       "the root (sidebar/deeplink) profile must post .closeProfile to return to my-tasks")
    }
}
