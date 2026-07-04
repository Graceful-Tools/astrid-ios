import XCTest
@testable import Astrid_App

/// Red-green spec for the deleted-task ledger semantics behind the
/// "deleted task reappears until restart" bug: ids are RETAINED after the
/// server confirms the delete (a fetch that started before the delete can
/// still deliver the task after it), stored ordered with oldest-first
/// eviction so the cap can never drop the id just recorded.
final class DeletedTaskLedgerTests: XCTestCase {
    func testAppendIsIdempotentAndOrdered() {
        var arr = TaskService.appendingDeletedIds([], ["t1", "t2"], cap: 500)
        XCTAssertEqual(arr, ["t1", "t2"])
        arr = TaskService.appendingDeletedIds(arr, ["t1"], cap: 500)
        XCTAssertEqual(arr, ["t1", "t2"], "re-record must not duplicate")
    }

    func testCapEvictsOldestNeverNewest() {
        let full = (0..<500).map { "old\($0)" }
        let arr = TaskService.appendingDeletedIds(full, ["newest"], cap: 500)
        XCTAssertEqual(arr.count, 500)
        XCTAssertTrue(arr.contains("newest"))
        XCTAssertFalse(arr.contains("old0"))
        XCTAssertEqual(arr.last, "newest")
    }

    func testMultipleAppendsPastCap() {
        var arr = (0..<499).map { "t\($0)" }
        arr = TaskService.appendingDeletedIds(arr, ["a", "b", "c"], cap: 500)
        XCTAssertEqual(arr.count, 500)
        XCTAssertEqual(Array(arr.suffix(3)), ["a", "b", "c"])
    }
}
