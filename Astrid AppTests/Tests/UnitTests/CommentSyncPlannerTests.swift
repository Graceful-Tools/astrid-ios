import XCTest
@testable import Astrid_App

/// Red-green spec for the comment sync planner (GitHub issue comments ↔
/// Astrid comments). The mapping is the loop breaker: pulled comments never
/// pull twice, and their Astrid twins never push back as duplicates.
final class CommentSyncPlannerTests: XCTestCase {
    private typealias Remote = CommentSyncPlanner.RemoteComment
    private typealias Local = CommentSyncPlanner.LocalComment

    private let r1 = Remote(id: "gh1", body: "from github", author: "jonparis")
    private let r2 = Remote(id: "gh2", body: "also github", author: "someone")
    private let l1 = Local(id: "c1", content: "from astrid", isSystem: false)
    private let lsys = Local(id: "c2", content: "Jon changed priority", isSystem: true)

    func testFreshSync_pullsAllRemote_pushesNonSystemLocal() {
        let plan = CommentSyncPlanner.plan(remote: [r1, r2], local: [l1, lsys], mapping: [:])
        XCTAssertEqual(plan.pullCreates, [r1, r2])
        XCTAssertEqual(plan.pushCreates, [l1])
    }

    func testMappedRemoteComment_doesNotRePull() {
        let plan = CommentSyncPlanner.plan(remote: [r1, r2], local: [l1], mapping: ["gh1": "cX"])
        XCTAssertEqual(plan.pullCreates, [r2])
    }

    func testMirroredComment_isNoOpBothDirections() {
        // The Astrid twin of a pulled GitHub comment must not push back —
        // that's the echo loop.
        let mirrored = Local(id: "cX", content: "mirrored", isSystem: false)
        let plan = CommentSyncPlanner.plan(remote: [r1], local: [mirrored], mapping: ["gh1": "cX"])
        XCTAssertTrue(plan.pullCreates.isEmpty)
        XCTAssertTrue(plan.pushCreates.isEmpty)
    }

    func testPushedLocalComment_doesNotPushTwice() {
        let plan = CommentSyncPlanner.plan(remote: [], local: [l1], mapping: ["gh9": "c1"])
        XCTAssertTrue(plan.pushCreates.isEmpty)
    }

    func testTempIdLocalComments_waitForReconcile() {
        let offline = Local(id: "temp_1", content: "offline", isSystem: false)
        let plan = CommentSyncPlanner.plan(remote: [], local: [offline], mapping: [:])
        XCTAssertTrue(plan.pushCreates.isEmpty)
    }

    func testMappingCodec_roundTrips() {
        let m = ["gh1": "c1", "gh2": "c2"]
        XCTAssertEqual(CommentSyncPlanner.decodeMapping(CommentSyncPlanner.encodeMapping(m)), m)
        XCTAssertEqual(CommentSyncPlanner.decodeMapping(nil), [:])
        XCTAssertEqual(CommentSyncPlanner.decodeMapping(""), [:])
    }

    func testPulledContent_carriesAttribution() {
        let content = CommentSyncPlanner.pulledContent(author: "jonparis", body: "hello")
        XCTAssertTrue(content.contains("jonparis"))
        XCTAssertTrue(content.contains("hello"))
    }
}
