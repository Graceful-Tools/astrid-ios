//  TaskWhenRowLayoutTests.swift
//  How the task detail's "When" controls are laid out across lines.
//
//  THE BUG: date, time and repeat were one HStack. Each chip sizes to its own
//  content and refuses to compress (`.fixedSize`), so the row's width is the sum
//  of three chips — and on a phone, inside a labelled row, that is more than
//  there is. Whichever chip came last got pushed off.
//
//  It was already tight; giving the date its weekday ("Wed, Aug 12, 2026"
//  instead of "Aug 12, 2026") is what pushed it over, and the TIME disappeared.
//  A layout that only works while the text stays short is not working.
//
//  So repeat wraps to its own line — the way a custom repeat's pattern already
//  did — and date and time keep the first line to themselves.

import XCTest
@testable import Astrid_App

final class TaskWhenRowLayoutTests: XCTestCase {

    // MARK: - THE BUG: the time must always have room

    /// Date and time share the first line, and nothing else competes with them.
    func testDateAndTimeShareTheFirstLine() {
        let lines = TaskWhenRowLayout.lines(hasDate: true, isCustomRepeat: false)
        XCTAssertEqual(lines.first, [.date, .time])
    }

    /// Stated as its own case because this is the actual report: the time went
    /// missing. It must be on the row for any dated task, whatever the repeat.
    func testTimeIsPresentForEveryDatedTask() {
        for isCustom in [true, false] {
            let controls = TaskWhenRowLayout.lines(hasDate: true, isCustomRepeat: isCustom).flatMap { $0 }
            XCTAssertTrue(controls.contains(.time),
                          "the time must not be squeezed off the row (custom repeat: \(isCustom))")
        }
    }

    /// Three chips on one line is what caused this. Never again.
    func testNoLineCarriesMoreThanTwoControls() {
        for hasDate in [true, false] {
            for isCustom in [true, false] {
                for line in TaskWhenRowLayout.lines(hasDate: hasDate, isCustomRepeat: isCustom) {
                    XCTAssertLessThanOrEqual(line.count, 2,
                                             "a third chip is what pushed the time off the row")
                }
            }
        }
    }

    // MARK: - Repeat wraps

    /// Repeat gets its own line rather than competing for the first one.
    func testRepeatWrapsToItsOwnLine() {
        let lines = TaskWhenRowLayout.lines(hasDate: true, isCustomRepeat: false)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.last, [.repeatPattern])
    }

    /// A CUSTOM repeat already had its own row below, showing the real pattern
    /// ("Every 2 weeks on Mon, Wed"). It must not also get a chip here — that
    /// would be a second, less informative control for the same thing.
    func testCustomRepeatDoesNotAlsoGetAChip() {
        let controls = TaskWhenRowLayout.lines(hasDate: true, isCustomRepeat: true).flatMap { $0 }
        XCTAssertFalse(controls.contains(.repeatPattern))
        XCTAssertEqual(controls, [.date, .time])
    }

    // MARK: - Undated tasks

    /// With no date there is nothing for a time or a repeat to attach to, so the
    /// row is a single "add a date" control rather than three inert ones.
    func testUndatedTaskShowsOnlyTheDateControl() {
        XCTAssertEqual(TaskWhenRowLayout.lines(hasDate: false, isCustomRepeat: false), [[.date]])
    }

    func testUndatedTaskIsOneLine() {
        XCTAssertEqual(TaskWhenRowLayout.lines(hasDate: false, isCustomRepeat: true).count, 1)
    }

    /// No layout ever produces an empty line — that would render as a blank gap.
    func testNoEmptyLines() {
        for hasDate in [true, false] {
            for isCustom in [true, false] {
                for line in TaskWhenRowLayout.lines(hasDate: hasDate, isCustomRepeat: isCustom) {
                    XCTAssertFalse(line.isEmpty)
                }
            }
        }
    }
}
