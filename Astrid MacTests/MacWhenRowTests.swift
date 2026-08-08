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

    // MARK: - The row's composition is the SHARED one

    /// The Mac renders the same lines iOS does. Its own `MacWhenControl` — which
    /// existed partly so the retired due-date toggle and inline quick-pick rows
    /// could be asserted absent — is gone: the shared enum has no cases for
    /// them, which is a stronger guarantee than a test.
    func testUndatedTaskShowsOnlyTheDateTrigger() {
        XCTAssertEqual(TaskWhenRowLayout.controls(hasDate: false, isCustomRepeat: false), [.date])
    }

    /// THE BUG: the three controls were forced onto one line, each with a
    /// minimum width so they would all fit a 380pt panel — which is exactly what
    /// truncated the date to "Sat, Aug 15,…". They wrap now, and only when they
    /// must: given room, all three stay on one line.
    func testControlsShareALineWhenTheyFitAndWrapWhenTheyDoNot() {
        XCTAssertEqual(FlowRows.rows(itemWidths: [150, 110, 88], maxWidth: 380, spacing: 10).count, 1)
        XCTAssertEqual(FlowRows.rows(itemWidths: [150, 110, 88], maxWidth: 280, spacing: 10).count, 2)
    }

    /// A custom repeat gets no chip: its real pattern is on its own line below,
    /// and that summary is now the control itself rather than dead text beside
    /// a separate "Edit" button.
    func testCustomRepeatGetsNoChipOnTheRow() {
        XCTAssertEqual(TaskWhenRowLayout.controls(hasDate: true, isCustomRepeat: true),
                       [.date, .time])
    }

    // MARK: - The popover carries what the pane used to

    /// "No due date" comes before every quick pick — not a toolbar escape hatch.
    /// The order iOS deliberately chose and DueDateQuickPicks documents as
    /// contractual. (The typed field precedes it, but that is a text input, not
    /// one of the choices.)
    func testClearingIsTheFirstChoiceInThePopover() {
        let rows = MacDueDatePopover.rows
        let clearIndex = rows.firstIndex(of: .clear)
        let firstPickIndex = rows.firstIndex { if case .quickPick = $0 { return true }; return false }
        XCTAssertNotNil(clearIndex)
        XCTAssertNotNil(firstPickIndex)
        XCTAssertLessThan(clearIndex!, firstPickIndex!,
                          "clearing must precede the quick picks")
    }

    /// This is a Mac: there is a keyboard, so a date can be TYPED rather than
    /// hunted for in a grid — and the field leads the popover.
    func testPopoverOffersATypableDateField() {
        XCTAssertEqual(MacDueDatePopover.rows.first, .typedEntry)
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

    /// THE BUG: the popover showed a typable field AND a graphical calendar.
    /// The field brings a calendar of its own when you use it, so choosing a
    /// date put two calendars on screen, one overlapping the other.
    func testPopoverOffersExactlyOneDateEntryControl() {
        XCTAssertEqual(MacDueDatePopover.dateEntryControls.count, 1,
                       "a typable field plus a graphical calendar is two calendars, "
                       + "because the field carries one")
    }

    /// And the one it keeps is the typable field — this is a Mac.
    func testTheDateEntryControlIsTheTypableField() {
        XCTAssertEqual(MacDueDatePopover.dateEntryControls, [.typedEntry])
    }

    /// The standalone graphical calendar is gone from the popover.
    func testThePopoverHasNoStandaloneCalendar() {
        XCTAssertFalse(MacDueDatePopover.rows.contains(.calendar))
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

    /// The recorded minimums describe the date/time pair — the two controls that
    /// must share a line for the row to be usable at all. Repeat may wrap.
    func testRowMinimumsDescribeTheDateAndTimePair() {
        XCTAssertEqual(MacDetailRowFit.whenRowMinimums.count, 2)
        XCTAssertTrue(MacDetailRowFit.fits(MacDetailRowFit.whenRowMinimums,
                                           in: MacLayout.detailPanelWidth))
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
