//  DueDateLabelTests.swift
//  The due-date trigger's text, stated once for both platforms.
//
//  The Mac task detail led its When row with a "Due Date" TOGGLE, so every task —
//  dated or not — spent a row saying the words "Due Date". iOS never did: it
//  shows the date itself, or the words "No due date", behind a calendar glyph.
//  Porting the iOS design to the Mac needs the label logic on both platforms,
//  and that logic is 70 lines of timezone-sensitive arithmetic that must NOT be
//  retyped — the same reasoning that put DueDateQuickPicks in shared Core.
//
//  The timezone half is the part worth pinning. An all-day task is stored at
//  midnight UTC, so reading it with a local calendar west of UTC lands it on the
//  previous day and the label says "Yesterday" for a task due today.

import XCTest
@testable import Astrid_App

final class DueDateLabelTests: XCTestCase {

    /// A fixed "now": 2026-08-08 17:00 local in Los Angeles (UTC-7), chosen
    /// because the local day and the UTC day differ at that hour — the exact
    /// condition the all-day handling exists for.
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func localCalendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private func utcMidnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: year, month: month, day: day,
                                             hour: 0, minute: 0, second: 0))!
    }

    private func localTime(_ year: Int, _ month: Int, _ day: Int,
                           _ hour: Int, zone: TimeZone) -> Date {
        localCalendar(zone).date(from: DateComponents(year: year, month: month, day: day,
                                                      hour: hour))!
    }

    // MARK: - THE ASK: no date must SAY no date

    /// The Mac's toggle is replaced by a trigger that reads "No due date" — the
    /// same words iOS uses, from the same key.
    func testNoDateReadsAsNoDueDate() {
        XCTAssertEqual(DueDateLabel.text(for: nil, isAllDay: true),
                       NSLocalizedString("picker.no_due_date", comment: ""))
    }

    /// Localised, never a literal — this reaches the screen on both platforms.
    func testLabelsComeFromTheStringsCatalogue() {
        let now = localTime(2026, 8, 8, 17, zone: losAngeles)
        XCTAssertEqual(DueDateLabel.text(for: utcMidnight(2026, 8, 8), isAllDay: true,
                                         now: now, localCalendar: localCalendar(losAngeles)),
                       NSLocalizedString("picker.today", comment: ""))
        XCTAssertEqual(DueDateLabel.text(for: utcMidnight(2026, 8, 9), isAllDay: true,
                                         now: now, localCalendar: localCalendar(losAngeles)),
                       NSLocalizedString("picker.tomorrow", comment: ""))
        XCTAssertEqual(DueDateLabel.text(for: utcMidnight(2026, 8, 7), isAllDay: true,
                                         now: now, localCalendar: localCalendar(losAngeles)),
                       NSLocalizedString("time.yesterday", comment: ""))
    }

    // MARK: - The timezone trap

    /// 17:00 in Los Angeles is already the NEXT day in UTC. An all-day task due
    /// today is stored at 2026-08-08T00:00Z; read with a naive local calendar it
    /// looks like yesterday. It must still say "Today".
    func testAllDayTaskDueTodaySaysTodayLateInTheDayWestOfUTC() {
        let now = localTime(2026, 8, 8, 17, zone: losAngeles)
        XCTAssertEqual(DueDateLabel.text(for: utcMidnight(2026, 8, 8), isAllDay: true,
                                         now: now, localCalendar: localCalendar(losAngeles)),
                       NSLocalizedString("picker.today", comment: ""),
                       "an all-day date is stored at UTC midnight and must be read in UTC")
    }

    /// The same instant east of UTC, where the local day runs ahead.
    func testAllDayTaskDueTodaySaysTodayEastOfUTC() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let now = localTime(2026, 8, 8, 8, zone: tokyo)
        XCTAssertEqual(DueDateLabel.text(for: utcMidnight(2026, 8, 8), isAllDay: true,
                                         now: now, localCalendar: localCalendar(tokyo)),
                       NSLocalizedString("picker.today", comment: ""))
    }

    /// A TIMED task carries a real instant, so it is compared in the local
    /// calendar — the opposite rule, and getting them the same way round is the
    /// whole point of sharing this.
    func testTimedTaskUsesTheLocalCalendar() {
        let now = localTime(2026, 8, 8, 9, zone: losAngeles)
        let thisAfternoon = localTime(2026, 8, 8, 15, zone: losAngeles)
        XCTAssertEqual(DueDateLabel.text(for: thisAfternoon, isAllDay: false,
                                         now: now, localCalendar: localCalendar(losAngeles)),
                       NSLocalizedString("picker.today", comment: ""))
    }

    // MARK: - Anything further out is a real date

    func testDistantDatesAreFormattedNotNamed() {
        let now = localTime(2026, 8, 8, 12, zone: losAngeles)
        let label = DueDateLabel.text(for: utcMidnight(2026, 12, 25), isAllDay: true,
                                      now: now, localCalendar: localCalendar(losAngeles))
        for named in ["picker.today", "picker.tomorrow", "time.yesterday"] {
            XCTAssertNotEqual(label, NSLocalizedString(named, comment: ""))
        }
        XCTAssertFalse(label.isEmpty)
    }

    /// A formatted all-day date must render in UTC too, or a December 25th task
    /// displays as the 24th for anyone west of UTC.
    func testFormattedAllDayDateDoesNotDriftAcrossTheDateLine() {
        let now = localTime(2026, 8, 8, 12, zone: losAngeles)
        let label = DueDateLabel.text(for: utcMidnight(2026, 12, 25), isAllDay: true,
                                      now: now, localCalendar: localCalendar(losAngeles))
        XCTAssertTrue(label.contains("25"),
                      "expected the 25th, got \(label) — the formatter dropped to local time")
    }
}
