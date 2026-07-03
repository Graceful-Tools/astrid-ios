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

    // MARK: - Attachments (red-green: attachment-only comments must push)

    func testPushBody_textOnlyIsVerbatim() {
        XCTAssertEqual(CommentSyncPlanner.pushBody(content: "hello", attachmentNames: []), "hello")
    }

    func testPushBody_attachmentOnlyNamesTheFile() {
        let body = CommentSyncPlanner.pushBody(content: "", attachmentNames: ["photo.jpg"])
        XCTAssertTrue(body.contains("photo.jpg"))
        XCTAssertFalse(body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testPushBody_textAndAttachmentsCompose() {
        let body = CommentSyncPlanner.pushBody(content: "see file", attachmentNames: ["a.pdf", "b.png"])
        XCTAssertTrue(body.contains("see file"))
        XCTAssertTrue(body.contains("a.pdf"))
        XCTAssertTrue(body.contains("b.png"))
    }

    func testPlan_attachmentOnlyCommentPushes_emptyCommentDoesNot() {
        let attachOnly = Local(id: "c1", content: "", isSystem: false, attachmentNames: ["f.jpg"])
        let empty = Local(id: "c2", content: "  ", isSystem: false, attachmentNames: [])
        let plan = CommentSyncPlanner.plan(remote: [], local: [attachOnly, empty], mapping: [:])
        XCTAssertEqual(plan.pushCreates, [attachOnly])
    }

    // MARK: - Edit sync (red-green: converge the non-canonical side)

    private typealias Entry = CommentSyncPlanner.MapEntry

    func testEdit_astridEditOnPushedPair_pushesToGitHub() {
        let local = Local(id: "cA", content: "edited in astrid", isSystem: false)
        let remote = Remote(id: "ghA", body: "old astrid text", author: "jonparis")
        let plan = CommentSyncPlanner.editPlan(
            remote: [remote], local: [local],
            entries: [Entry(remoteId: "ghA", localId: "cA", pushed: true)])
        XCTAssertEqual(plan.pushUpdates.count, 1)
        XCTAssertEqual(plan.pushUpdates.first?.remoteId, "ghA")
        XCTAssertEqual(plan.pushUpdates.first?.body, "edited in astrid")
        XCTAssertTrue(plan.pullUpdates.isEmpty)
    }

    func testEdit_githubEditOnPulledPair_updatesLocalTwin() {
        let remote = Remote(id: "ghB", body: "edited on github", author: "jonparis")
        let local = Local(
            id: "cB",
            content: CommentSyncPlanner.pulledContent(author: "jonparis", body: "old github text"),
            isSystem: false)
        let plan = CommentSyncPlanner.editPlan(
            remote: [remote], local: [local],
            entries: [Entry(remoteId: "ghB", localId: "cB", pushed: false)])
        XCTAssertEqual(plan.pullUpdates.count, 1)
        XCTAssertEqual(plan.pullUpdates.first?.localId, "cB")
        XCTAssertEqual(
            plan.pullUpdates.first?.content,
            CommentSyncPlanner.pulledContent(author: "jonparis", body: "edited on github"))
        XCTAssertTrue(plan.pushUpdates.isEmpty)
    }

    func testEdit_inSyncPairsAreNoOps() {
        let pushed = CommentSyncPlanner.editPlan(
            remote: [Remote(id: "ghA", body: "same", author: "j")],
            local: [Local(id: "cA", content: "same", isSystem: false)],
            entries: [Entry(remoteId: "ghA", localId: "cA", pushed: true)])
        XCTAssertTrue(pushed.pushUpdates.isEmpty && pushed.pullUpdates.isEmpty)
        let twin = CommentSyncPlanner.pulledContent(author: "j", body: "same")
        let pulled = CommentSyncPlanner.editPlan(
            remote: [Remote(id: "ghB", body: "same", author: "j")],
            local: [Local(id: "cB", content: twin, isSystem: false)],
            entries: [Entry(remoteId: "ghB", localId: "cB", pushed: false)])
        XCTAssertTrue(pulled.pushUpdates.isEmpty && pulled.pullUpdates.isEmpty)
    }

    func testEdit_missingCounterpartIsSkipped() {
        let plan = CommentSyncPlanner.editPlan(
            remote: [], local: [Local(id: "cA", content: "x", isSystem: false)],
            entries: [Entry(remoteId: "ghA", localId: "cA", pushed: true)])
        XCTAssertTrue(plan.pushUpdates.isEmpty && plan.pullUpdates.isEmpty)
    }

    func testEntriesCodec_roundTripsWithDirection_legacyDecodesAsPushed() {
        let entries = [
            Entry(remoteId: "ghA", localId: "cA", pushed: true),
            Entry(remoteId: "ghB", localId: "cB", pushed: false),
        ]
        XCTAssertEqual(CommentSyncPlanner.decodeEntries(CommentSyncPlanner.encodeEntries(entries)), entries)
        XCTAssertEqual(
            CommentSyncPlanner.decodeEntries("gh1=c1"),
            [Entry(remoteId: "gh1", localId: "c1", pushed: true)])
    }

    func testPulledContent_carriesAttribution() {
        let content = CommentSyncPlanner.pulledContent(author: "jonparis", body: "hello")
        XCTAssertTrue(content.contains("jonparis"))
        XCTAssertTrue(content.contains("hello"))
    }
}
