//  MacWhenRowTests.swift
//  The Mac task detail's "When" row, rebuilt to match iOS.
//
//  What it was: a "Due Date" TOGGLE led the row, so every task spent a row
//  saying the words "Due Date" whether or not it had one. Switching the toggle
//  on unfolded the whole apparatus INTO the detail pane — a date picker, a row
//  of Today/Tomorrow/In 3 days/Next week chips, a row of time chips, and an
//  "All day" toggle — so the pane's layout changed shape depending on a task's
//  dates.
//
//  What iOS does, and what this now does: the row is a calendar glyph and ONE
//  trigger, reading the date or the words "No due date". Everything else lives
//  in the popover the trigger opens. The pane's shape stops depending on
//  whether a task has a date.
//
//  These tests pin the composition, because "the quick picks are in the popover"
//  is exactly the kind of thing a later refactor puts back inline by accident.

import XCTest
@testable import Astrid_Mac

final class MacWhenRowTests: XCTestCase {

    // MARK: - THE BUG: the row led with a toggle

    /// An undated task offers ONE control — the trigger. Not a toggle, and not
    /// a time or repeat control with nothing to attach to.
    func testUndatedTaskShowsOnlyTheDateTrigger() {
        XCTAssertEqual(MacWhenRow.controls(hasDate: false), [.date])
    }

    /// With a date, time and repeat join it — the iOS row, in the iOS order.
    func testDatedTaskShowsDateThenTimeThenRepeat() {
        XCTAssertEqual(MacWhenRow.controls(hasDate: true), [.date, .time, .repeatPattern])
    }

    /// The toggle is gone in both states. It is not a control the row can offer.
    func testNoDueDateToggleInEitherState() {
        for hasDate in [true, false] {
            XCTAssertFalse(MacWhenRow.controls(hasDate: hasDate).contains(.dueDateToggle),
                           "the row must never lead with a toggle again (hasDate: \(hasDate))")
        }
    }

    /// THE BUG, stated directly: quick picks must not be laid out in the detail
    /// pane. They belong to the popover.
    func testQuickPicksAreNeverInlineInTheDetailPane() {
        for hasDate in [true, false] {
            let controls = MacWhenRow.controls(hasDate: hasDate)
            XCTAssertFalse(controls.contains(.dateQuickPicks))
            XCTAssertFalse(controls.contains(.timeQuickPicks))
            XCTAssertFalse(controls.contains(.allDayToggle))
        }
    }

    /// The pane's shape must not depend on whether a task has a date — the row
    /// grows by controls on one line, never by unfolding extra rows.
    func testTheRowIsAlwaysASingleLine() {
        XCTAssertLessThanOrEqual(MacWhenRow.controls(hasDate: true).count, 3)
    }

    // MARK: - The popover carries what the pane used to

    /// "No due date" is the FIRST row, not a toolbar escape hatch — the order
    /// iOS deliberately chose and DueDateQuickPicks documents as contractual.
    func testClearingIsTheFirstChoiceInThePopover() {
        XCTAssertEqual(MacDueDatePopover.rows.first, .clear)
    }

    /// The popover offers exactly the shared quick picks, in the shared order —
    /// so the Mac cannot drift from iOS about what "Next week" means.
    func testPopoverOffersTheSharedQuickPicksInOrder() {
        let picks: [DueDateQuickPicks.DateOption] = MacDueDatePopover.rows.compactMap {
            if case .quickPick(let option) = $0 { return option }
            return nil
        }
        XCTAssertEqual(picks, DueDateQuickPicks.dateOptions)
    }

    /// And the calendar itself is there, last — tapping the trigger opens the
    /// picker, which is the whole point of the control.
    func testPopoverEndsWithTheCalendar() {
        XCTAssertEqual(MacDueDatePopover.rows.last, .calendar)
    }

    // MARK: - The time popover mirrors it

    /// Clearing the time is what "all day" now means; the standalone All-day
    /// toggle is gone, exactly as on iOS.
    func testTimePopoverLeadsWithClearingTheTime() {
        XCTAssertEqual(MacDueTimePopover.rows.first, .clear)
    }

    func testTimePopoverOffersTheSharedTimeQuickPicksInOrder() {
        let picks: [DueDateQuickPicks.TimeOption] = MacDueTimePopover.rows.compactMap {
            if case .quickPick(let option) = $0 { return option }
            return nil
        }
        XCTAssertEqual(picks, DueDateQuickPicks.timeOptions)
    }

    // MARK: - It still has to fit the panel

    /// The row's controls changed, so the width arithmetic from task 42013da7
    /// has to be re-satisfied — that bug clipped every line of the detail off
    /// its left edge.
    func testTheRebuiltRowStillFitsTheDetailPanel() {
        XCTAssertTrue(MacDetailRowFit.fits(MacDetailRowFit.whenRowMinimums,
                                           in: MacLayout.detailPanelWidth),
                      "the When row needs \(MacDetailRowFit.required(MacDetailRowFit.whenRowMinimums))pt "
                      + "of a \(MacLayout.detailPanelWidth)pt panel")
    }

    /// One minimum per control actually on the row.
    func testRowMinimumsCoverExactlyTheControlsOnTheRow() {
        XCTAssertEqual(MacDetailRowFit.whenRowMinimums.count,
                       MacWhenRow.controls(hasDate: true).count)
    }

    // MARK: - Storage conversion
    //
    // An all-day task stores midnight UTC; a date picker speaks the user's local
    // calendar. Every crossing needs converting, and the failure mode is quiet:
    // the task moves a day rather than throwing anything.

    private var losAngeles: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Picking the 8th in the calendar must STORE the 8th, not the 7th, for a
    /// user seven hours behind UTC.
    func testPickingADayStoresThatDayAtUTCMidnight() {
        let localEighth = losAngeles.date(from: DateComponents(year: 2026, month: 8, day: 8,
                                                               hour: 14))!
        let stored = MacWhenDate.utcMidnight(ofLocalDay: localEighth, calendar: losAngeles)

        let components = utc.dateComponents([.year, .month, .day, .hour], from: stored)
        XCTAssertEqual(components.day, 8, "the stored day drifted")
        XCTAssertEqual(components.hour, 0, "an all-day task stores midnight UTC")
    }

    /// And back the other way, so the calendar highlights the square the task is
    /// actually due on.
    func testAnAllDayDateReadsBackAsTheSameLocalDay() {
        let stored = utc.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 0))!
        let shown = MacWhenDate.localDay(ofAllDay: stored, calendar: losAngeles)
        XCTAssertEqual(losAngeles.dateComponents([.year, .month, .day], from: shown).day, 8)
    }

    /// The round trip is lossless — the property that actually matters, since
    /// every edit makes this trip.
    func testLocalDayAndUTCMidnightRoundTrip() {
        for day in 1...28 {
            let stored = utc.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 0))!
            let back = MacWhenDate.utcMidnight(
                ofLocalDay: MacWhenDate.localDay(ofAllDay: stored, calendar: losAngeles),
                calendar: losAngeles)
            XCTAssertEqual(back, stored, "day \(day) did not survive the round trip")
        }
    }

    /// Setting a TIME must not move the DAY. Splicing 09:00 onto a task due the
    /// 8th keeps the 8th.
    func testSettingATimeKeepsTheDay() {
        let day = losAngeles.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 0))!
        let nineAM = losAngeles.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 9))!
        let result = MacWhenDate.combining(day: day, timeFrom: nineAM, calendar: losAngeles)

        let components = losAngeles.dateComponents([.day, .hour], from: result)
        XCTAssertEqual(components.day, 8)
        XCTAssertEqual(components.hour, 9)
    }

    /// And setting a DAY must not move the TIME — a task due at 15:00 moved to
    /// tomorrow is still due at 15:00.
    func testChangingTheDayKeepsTheTime() {
        let existing = losAngeles.date(from: DateComponents(year: 2026, month: 8, day: 8,
                                                            hour: 15, minute: 30))!
        let tomorrow = losAngeles.date(from: DateComponents(year: 2026, month: 8, day: 9,
                                                            hour: 0))!
        let result = MacWhenDate.combining(day: tomorrow, timeFrom: existing, calendar: losAngeles)

        let components = losAngeles.dateComponents([.day, .hour, .minute], from: result)
        XCTAssertEqual(components.day, 9)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 30)
    }

    /// With no time to carry, the day is left exactly as given.
    func testCombiningWithoutATimeLeavesTheDayAlone() {
        let day = losAngeles.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 11))!
        XCTAssertEqual(MacWhenDate.combining(day: day, timeFrom: nil, calendar: losAngeles), day)
    }
}
