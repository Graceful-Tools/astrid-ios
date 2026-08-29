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

    // MARK: - Delete sync (canonical side's absence deletes the mirror)

    func testDelete_localGoneOnPushedPair_deletesRemoteMirror() {
        let plan = CommentSyncPlanner.deletePlan(
            remoteIds: ["gA", "gB"], localIds: ["cB"],
            entries: [Entry(remoteId: "gA", localId: "cA", pushed: true),
                      Entry(remoteId: "gB", localId: "cB", pushed: false)])
        XCTAssertEqual(plan.deleteRemoteIds, ["gA"])
        XCTAssertTrue(plan.deleteLocalIds.isEmpty)
        XCTAssertEqual(plan.survivingEntries, [Entry(remoteId: "gB", localId: "cB", pushed: false)])
    }

    func testDelete_remoteGoneOnPulledPair_deletesLocalTwin() {
        let plan = CommentSyncPlanner.deletePlan(
            remoteIds: ["gA"], localIds: ["cA", "cB"],
            entries: [Entry(remoteId: "gA", localId: "cA", pushed: true),
                      Entry(remoteId: "gB", localId: "cB", pushed: false)])
        XCTAssertEqual(plan.deleteLocalIds, ["cB"])
        XCTAssertTrue(plan.deleteRemoteIds.isEmpty)
    }

    func testDelete_intactPairsUntouched() {
        let entries = [Entry(remoteId: "gA", localId: "cA", pushed: true),
                       Entry(remoteId: "gB", localId: "cB", pushed: false)]
        let plan = CommentSyncPlanner.deletePlan(
            remoteIds: ["gA", "gB"], localIds: ["cA", "cB"], entries: entries)
        XCTAssertTrue(plan.deleteLocalIds.isEmpty && plan.deleteRemoteIds.isEmpty)
        XCTAssertEqual(plan.survivingEntries, entries)
    }

    func testDelete_mirrorAbsenceNeverDeletesTheOriginal() {
        // Remote mirror of a pushed pair vanished: the local original stays
        // (a future pass may re-push; deleting the original would lose data).
        let plan = CommentSyncPlanner.deletePlan(
            remoteIds: [], localIds: ["cA"],
            entries: [Entry(remoteId: "gA", localId: "cA", pushed: true)])
        XCTAssertTrue(plan.deleteLocalIds.isEmpty)
    }

    // MARK: - Echo loop (Task: ab77476c) — the sync must recognise its own writes

    func testMirroredComment_neverPushesBack_evenWithNoMapping_ab77476c() {
        // The map is the only loop breaker today; when its write is lost the
        // Astrid twin of a GitHub comment pushed back, and the round trip
        // stacked another "**jonparis** (GitHub):" prefix every ~3 seconds.
        let twin = Local(
            id: "cX",
            content: CommentSyncPlanner.pulledContent(author: "jonparis", body: "from github"),
            isSystem: false)
        let plan = CommentSyncPlanner.plan(remote: [r1], local: [twin], mapping: [:])
        XCTAssertTrue(plan.pushCreates.isEmpty, "a mirrored comment must never push back to GitHub")
    }

    func testStackedPrefixComment_neverPushesBack_ab77476c() {
        let stacked = Local(
            id: "cX",
            content: CommentSyncPlanner.pulledContent(
                author: "jonparis",
                body: CommentSyncPlanner.pulledContent(author: "jonparis", body: "from github")),
            isSystem: false)
        let plan = CommentSyncPlanner.plan(remote: [], local: [stacked], mapping: [:])
        XCTAssertTrue(plan.pushCreates.isEmpty)
    }

    func testLostMapping_adoptsExistingMirror_insteadOfPullingAgain_ab77476c() {
        let twin = Local(
            id: "cX",
            content: CommentSyncPlanner.pulledContent(author: "jonparis", body: "from github"),
            isSystem: false)
        let plan = CommentSyncPlanner.plan(remote: [r1], local: [twin], mapping: [:])
        XCTAssertTrue(plan.pullCreates.isEmpty, "the mirror already exists — re-pulling duplicates it")
        XCTAssertEqual(plan.adoptions, [Entry(remoteId: "gh1", localId: "cX", pushed: false)])
    }

    func testLostMapping_recognisesItsOwnPush_insteadOfReIngestingIt_ab77476c() {
        // Our push came back on the next pull as an unmapped remote comment.
        // Ingesting it would create a prefixed copy of Jon's own comment,
        // which then looks like a mirror — the other half of the echo.
        let echo = Remote(id: "gh9", body: "from astrid", author: "jonparis")
        let plan = CommentSyncPlanner.plan(remote: [echo], local: [l1], mapping: [:])
        XCTAssertTrue(plan.pullCreates.isEmpty)
        XCTAssertTrue(plan.pushCreates.isEmpty)
        XCTAssertEqual(plan.adoptions, [Entry(remoteId: "gh9", localId: "c1", pushed: true)])
    }

    func testAdoption_claimsEachLocalCommentOnce_ab77476c() {
        // Two GitHub comments with the same body must not both adopt the one
        // local mirror; the second is a genuine new comment.
        let body = "from github"
        let twin = Local(
            id: "cX",
            content: CommentSyncPlanner.pulledContent(author: "jonparis", body: body),
            isSystem: false)
        let dupe = Remote(id: "gh2", body: body, author: "jonparis")
        let plan = CommentSyncPlanner.plan(remote: [r1, dupe], local: [twin], mapping: [:])
        XCTAssertEqual(plan.adoptions.count, 1)
        XCTAssertEqual(plan.pullCreates, [dupe])
    }

    func testGenuineRemoteComment_stillPulls_ab77476c() {
        let plan = CommentSyncPlanner.plan(remote: [r1, r2], local: [l1], mapping: [:])
        XCTAssertEqual(plan.pullCreates, [r1, r2])
        XCTAssertEqual(plan.pushCreates, [l1])
        XCTAssertTrue(plan.adoptions.isEmpty)
    }

    func testPulledContent_carriesAttribution() {
        let content = CommentSyncPlanner.pulledContent(author: "jonparis", body: "hello")
        XCTAssertTrue(content.contains("jonparis"))
        XCTAssertTrue(content.contains("hello"))
    }
}
