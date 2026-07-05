import XCTest
@testable import Astrid_App

/// Locks the cross-container push guard (review finding C1): a task shared
/// across, or moved between, two linked lists must not have its link for
/// container A pushed during container B's sync pass — that PATCHes the wrong
/// remote item (GitHub: clobbers an unrelated issue #; Google: 404-loops).
final class SyncContainerGuardTests: XCTestCase {

    func testPushesWhenContainersMatch() {
        XCTAssertTrue(SyncContainerGuard.mayPush(
            linkContainerId: "octo/repo", passContainerId: "octo/repo"))
        XCTAssertTrue(SyncContainerGuard.mayPush(
            linkContainerId: "TASKLIST_ABC", passContainerId: "TASKLIST_ABC"))
    }

    func testSkipsWhenContainersDiffer() {
        // GitHub: repoA link during repoB pass — the corruption case.
        XCTAssertFalse(SyncContainerGuard.mayPush(
            linkContainerId: "octo/repoA", passContainerId: "octo/repoB"))
        // Google: default tasklist link during a real-list pass.
        XCTAssertFalse(SyncContainerGuard.mayPush(
            linkContainerId: "TASKLIST_DEFAULT", passContainerId: "TASKLIST_WORK"))
    }
}
