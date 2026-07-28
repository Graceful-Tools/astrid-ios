//  MacCheckboxAssetTests.swift
//  Regression tests for Task ca13c94b — "[mac] repeating tasks don't have the repeating checkbox".
//
//  iOS (TaskRowView.checkboxImage) and web (task-checkbox.tsx) both build the name
//  check_box[_repeat][_checked]_<priority> from the shared asset catalog, so a repeating task shows
//  a box with arrow corners. The Mac drew its own rounded rect and had no notion of repeating.

import XCTest
import AppKit
@testable import Astrid_Mac

final class MacCheckboxAssetTests: XCTestCase {

    /// The name is built exactly as iOS and web build it — same order, same tokens.
    func testNameMatchesTheSharedConvention() {
        XCTAssertEqual(MacCheckboxAsset.name(priority: 0, completed: false, repeating: false), "check_box_0")
        XCTAssertEqual(MacCheckboxAsset.name(priority: 2, completed: true, repeating: false), "check_box_checked_2")
        XCTAssertEqual(MacCheckboxAsset.name(priority: 1, completed: false, repeating: true), "check_box_repeat_1")
        XCTAssertEqual(MacCheckboxAsset.name(priority: 3, completed: true, repeating: true), "check_box_repeat_checked_3")
    }

    /// A repeating task never renders the plain box — that omission is the bug.
    func testRepeatingAlwaysPicksARepeatAsset() {
        for priority in 0...3 {
            for completed in [true, false] {
                let name = MacCheckboxAsset.name(priority: priority, completed: completed, repeating: true)
                XCTAssertTrue(name.contains("_repeat"), "\(name) drops the repeat affordance")
            }
        }
    }

    /// Out-of-range priorities fall back rather than naming an asset that does not exist.
    func testPriorityIsClampedToTheAssetsThatExist() {
        XCTAssertEqual(MacCheckboxAsset.name(priority: 9, completed: false, repeating: false), "check_box_0")
        XCTAssertEqual(MacCheckboxAsset.name(priority: -1, completed: false, repeating: false), "check_box_0")
    }

    /// Every one of the 16 images must resolve in the MAC bundle. If the catalog were not a member
    /// of the Mac target these would all be nil, the drawn fallback would render, and the bug would
    /// look fixed while showing nothing new.
    func testAllSixteenAssetsResolveInTheMacBundle() {
        for priority in 0...3 {
            for completed in [true, false] {
                for repeating in [true, false] {
                    let name = MacCheckboxAsset.name(priority: priority, completed: completed, repeating: repeating)
                    XCTAssertNotNil(NSImage(named: name), "\(name) is missing from the Mac bundle")
                }
            }
        }
    }

    /// The predicate iOS uses: `.never` is not repeating.
    func testNeverIsNotRepeating() {
        XCTAssertFalse(MacCheckboxAsset.isRepeating(nil))
        XCTAssertFalse(MacCheckboxAsset.isRepeating(.never))
        XCTAssertTrue(MacCheckboxAsset.isRepeating(.daily))
        XCTAssertTrue(MacCheckboxAsset.isRepeating(.custom))
    }
}
