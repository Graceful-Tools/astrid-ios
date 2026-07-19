//  MacReorderTests.swift
//  Astrid for Mac — Task 7b7a17d3: within-list manual reorder computation.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacReorderTests: XCTestCase {

    func testMoveDown() {
        // Move item at index 0 to the end (SwiftUI destination is the pre-removal index).
        XCTAssertEqual(MacReorder.reordered(["a", "b", "c"], from: IndexSet(integer: 0), to: 3),
                       ["b", "c", "a"])
    }

    func testMoveUp() {
        XCTAssertEqual(MacReorder.reordered(["a", "b", "c"], from: IndexSet(integer: 2), to: 0),
                       ["c", "a", "b"])
    }

    func testNoOp() {
        XCTAssertEqual(MacReorder.reordered(["a", "b", "c"], from: IndexSet(integer: 1), to: 1),
                       ["a", "b", "c"])
    }
}
#endif
