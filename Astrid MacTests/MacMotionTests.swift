//  MacMotionTests.swift
//  Astrid for Mac — Task 4c7b9f08: motion stays subtle/native (0.15–0.3s band) and ordered.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacMotionTests: XCTestCase {

    func testDurationsStaySubtle() {
        XCTAssertGreaterThanOrEqual(MacMotion.fastDuration, 0.1)
        XCTAssertLessThanOrEqual(MacMotion.fastDuration, 0.2)
        XCTAssertLessThanOrEqual(MacMotion.mediumDuration, 0.3, "State changes must not feel slow")
        XCTAssertLessThanOrEqual(MacMotion.springResponse, 0.35)
    }

    func testFastIsFasterThanMedium() {
        XCTAssertLessThan(MacMotion.fastDuration, MacMotion.mediumDuration)
    }
}
#endif
