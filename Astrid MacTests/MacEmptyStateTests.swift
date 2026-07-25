//  MacEmptyStateTests.swift
//  Astrid for Mac — Task 1c3562e9: branded empty-state copy per context.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacEmptyStateTests: XCTestCase {

    func testEveryContextHasFriendlyCopy() {
        let all: [MacEmptyCopy] = [.noTasks, .filteredOut, .noListSelected, .chatEmpty]
        for c in all {
            XCTAssertFalse(c.message.isEmpty)
            XCTAssertGreaterThan(c.message.count, 10, "Copy should be a friendly sentence, not a label")
        }
        // Messages are distinct per context.
        XCTAssertEqual(Set(all.map(\.message)).count, all.count)
    }

    func testFilteredOutExplainsHow() {
        XCTAssertNotNil(MacEmptyCopy.filteredOut.detail, "Filtered-out state must point at the filter control")
        XCTAssertNil(MacEmptyCopy.noTasks.detail)
    }
}
#endif
