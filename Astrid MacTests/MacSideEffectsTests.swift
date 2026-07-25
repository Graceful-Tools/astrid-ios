//  MacSideEffectsTests.swift
//  Astrid for Mac — Task c38b177b: reschedule notifications only when the due-date shape changes.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSideEffectsTests: XCTestCase {

    private func task(_ id: String, due: Date? = nil, completed: Bool = false, title: String = "t") -> Task {
        var t = Task(id: id, title: title, completed: completed)
        t.dueDateTime = due
        return t
    }

    func testTitleEditDoesNotChangeSignature() {
        let due = Date(timeIntervalSince1970: 1_000_000)
        let a = [task("1", due: due, title: "old"), task("2")]
        let b = [task("1", due: due, title: "NEW TITLE"), task("2")]
        XCTAssertEqual(MacSideEffects.dueSignature(a), MacSideEffects.dueSignature(b),
                       "Title edits must not trigger a full notification reschedule")
    }

    func testDueChangeChangesSignature() {
        let a = [task("1", due: Date(timeIntervalSince1970: 1_000_000))]
        let b = [task("1", due: Date(timeIntervalSince1970: 2_000_000))]
        XCTAssertNotEqual(MacSideEffects.dueSignature(a), MacSideEffects.dueSignature(b))
    }

    func testCompletingADueTaskChangesSignature() {
        let due = Date(timeIntervalSince1970: 1_000_000)
        let a = [task("1", due: due)]
        let b = [task("1", due: due, completed: true)]   // completed → no reminder needed
        XCTAssertNotEqual(MacSideEffects.dueSignature(a), MacSideEffects.dueSignature(b))
    }

    func testOrderIndependent() {
        let d1 = Date(timeIntervalSince1970: 1), d2 = Date(timeIntervalSince1970: 2)
        XCTAssertEqual(MacSideEffects.dueSignature([task("1", due: d1), task("2", due: d2)]),
                       MacSideEffects.dueSignature([task("2", due: d2), task("1", due: d1)]))
    }

    func testUndatedTasksDoNotAffectSignature() {
        let due = Date(timeIntervalSince1970: 5)
        XCTAssertEqual(MacSideEffects.dueSignature([task("1", due: due)]),
                       MacSideEffects.dueSignature([task("1", due: due), task("9")]))
    }
}
#endif
