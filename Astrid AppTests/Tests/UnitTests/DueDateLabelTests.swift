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

    /// THE ASK: a formatted date carries its day of week. "Aug 12, 2026" tells
    /// you when in the abstract; whether that is a Wednesday is the thing you
    /// actually need when scheduling, and nothing else on the row says it.
    func testFormattedDatesCarryTheDayOfWeek() {
        let now = localTime(2026, 8, 8, 12, zone: losAngeles)
        // 12 Aug 2026 is a Wednesday.
        let label = DueDateLabel.text(for: utcMidnight(2026, 8, 12), isAllDay: true,
                                      now: now, localCalendar: localCalendar(losAngeles))
        XCTAssertTrue(label.contains("Wed"),
                      "expected the weekday in \(label)")
    }

    /// Today/Tomorrow/Yesterday already answer "when", so they stay as they are
    /// rather than growing a redundant weekday.
    func testNamedDaysDoNotGainAWeekday() {
        let now = localTime(2026, 8, 8, 12, zone: losAngeles)
        XCTAssertEqual(DueDateLabel.text(for: utcMidnight(2026, 8, 8), isAllDay: true,
                                         now: now, localCalendar: localCalendar(losAngeles)),
                       NSLocalizedString("picker.today", comment: ""))
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

/// A list's default time of day — used when a date is put on an existing task,
/// which must take the list's default rather than the current clock.
final class NewTaskDefaultTimeOfDayTests: XCTestCase {

    func testParsesAValidTime() {
        let time = NewTaskDefaults.timeOfDay("09:30")
        XCTAssertEqual(time?.hour, 9)
        XCTAssertEqual(time?.minute, 30)
    }

    func testMidnightIsAValidDefault() {
        XCTAssertEqual(NewTaskDefaults.timeOfDay("00:00")?.hour, 0)
    }

    /// No default means all-day, not "midnight".
    func testMissingOrEmptyMeansNoDefault() {
        XCTAssertNil(NewTaskDefaults.timeOfDay(nil))
        XCTAssertNil(NewTaskDefaults.timeOfDay(""))
    }

    /// Garbage on the wire must not become a real time — an out-of-range hour
    /// would otherwise be handed to Calendar and silently roll the date.
    func testNonsenseIsRejected() {
        XCTAssertNil(NewTaskDefaults.timeOfDay("nine"))
        XCTAssertNil(NewTaskDefaults.timeOfDay("9"))
        XCTAssertNil(NewTaskDefaults.timeOfDay("25:00"))
        XCTAssertNil(NewTaskDefaults.timeOfDay("09:75"))
        XCTAssertNil(NewTaskDefaults.timeOfDay("-1:30"))
    }
}

// MARK: - Task c035ea55 (AITD-317)
//
// Five surfaces re-implemented this label by hand: CompactTaskRow, TaskRowView, the two chat
// views, and MacTaskRow. Each got something wrong.
//
// The user-visible one was CompactTaskRow. It ran `Calendar.current.isDateInToday` on the raw
// stored date with no `isAllDay` handling at all — and an all-day task is stored at midnight UTC,
// which is the PREVIOUS EVENING anywhere west of UTC. So for every user in the Americas, an
// all-day task due today read "Yesterday", and one due tomorrow read "Today". MacTaskRow had the
// same bug in its formatter: it printed an all-day date in the user's own zone, so 25 December
// showed as the 24th.
//
// The other three wrote "Today" / "Tomorrow" / "Yesterday" as English literals, in an app that
// ships in 12 languages, plus hardcoded American time patterns.

final class DueDateLabelSharedSurfaceTests: XCTestCase {

    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let utc = TimeZone(identifier: "UTC")!

    private func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// Midnight UTC on the given day — how an all-day task is stored.
    private func allDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar(utc).date(from: DateComponents(year: year, month: month, day: day,
                                                hour: 0, minute: 0, second: 0))!
    }

    /// A real instant, in Los Angeles local time.
    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar(losAngeles).date(from: DateComponents(year: year, month: month, day: day,
                                                       hour: hour, minute: minute))!
    }

    // MARK: - The bug CompactTaskRow shipped

    func testAnAllDayTaskDueTodayReadsTodayWestOfUTC() {
        // 21:00 in Los Angeles on 8 August. In UTC it is already the 9th, and the task's stored
        // instant (2026-08-08T00:00Z) is 17:00 on the 7th locally — which is what made the old
        // code say "Yesterday".
        let now = instant(2026, 8, 8, 21)

        XCTAssertEqual(
            DueDateLabel.rowText(for: allDay(2026, 8, 8), isAllDay: true,
                                 now: now, localCalendar: calendar(losAngeles)),
            NSLocalizedString("time.today", comment: ""),
            "an all-day task due today must not read Yesterday in the Americas"
        )
    }

    func testAnAllDayTaskDueTomorrowDoesNotReadToday() {
        let now = instant(2026, 8, 8, 21)

        XCTAssertEqual(
            DueDateLabel.rowText(for: allDay(2026, 8, 9), isAllDay: true,
                                 now: now, localCalendar: calendar(losAngeles)),
            NSLocalizedString("time.tomorrow", comment: "")
        )
    }

    func testAnAllDayTaskDueYesterdayStillReadsYesterday() {
        let now = instant(2026, 8, 8, 21)

        XCTAssertEqual(
            DueDateLabel.rowText(for: allDay(2026, 8, 7), isAllDay: true,
                                 now: now, localCalendar: calendar(losAngeles)),
            NSLocalizedString("time.yesterday", comment: "")
        )
    }

    func testTheBugIsSpecificallyTheMissingAllDayHandling() {
        // The same instant read as a TIMED date genuinely is yesterday evening locally. The label
        // must differ between the two readings — that difference is the whole point of isAllDay.
        let now = instant(2026, 8, 8, 21)
        let stored = allDay(2026, 8, 8)
        let cal = calendar(losAngeles)

        XCTAssertEqual(DueDateLabel.rowText(for: stored, isAllDay: true, now: now, localCalendar: cal),
                       NSLocalizedString("time.today", comment: ""))
        XCTAssertEqual(DueDateLabel.rowText(for: stored, isAllDay: false, now: now, localCalendar: cal),
                       NSLocalizedString("time.yesterday", comment: ""))
    }

    // MARK: - A far-off all-day date must print the day it is stored on

    func testAFarOffAllDayDateFormatsInUTCNotTheUsersZone() {
        // MacTaskRow's bug: 25 December, formatted in Los Angeles, is the 24th.
        let now = instant(2026, 8, 8, 21)
        let christmas = allDay(2026, 12, 25)

        for text in [
            DueDateLabel.rowText(for: christmas, isAllDay: true, now: now, localCalendar: calendar(losAngeles)),
            DueDateLabel.rowMediumText(for: christmas, isAllDay: true, now: now, localCalendar: calendar(losAngeles)),
        ] {
            XCTAssertTrue(text.contains("25"), "\(text) should name the 25th, not the 24th")
            XCTAssertFalse(text.contains("24"))
        }
    }

    func testATimedDateKeepsItsTimeAndTheUsersZone() {
        let now = instant(2026, 8, 8, 9)
        let text = DueDateLabel.rowMediumText(for: instant(2026, 8, 8, 14, 30), isAllDay: false,
                                              now: now, localCalendar: calendar(losAngeles))

        XCTAssertTrue(text.hasPrefix(NSLocalizedString("time.today", comment: "")))
        XCTAssertTrue(text.count > NSLocalizedString("time.today", comment: "").count,
                      "a timed task must still show its time of day")
    }

    func testAnAllDayDateCarriesNoTimeOfDay() {
        let now = instant(2026, 8, 8, 9)
        XCTAssertEqual(
            DueDateLabel.rowMediumText(for: allDay(2026, 8, 8), isAllDay: true,
                                       now: now, localCalendar: calendar(losAngeles)),
            NSLocalizedString("time.today", comment: ""),
            "an all-day task has no time to show"
        )
    }

    // MARK: - Chat

    func testAChatHeadingNamesTodayAndYesterday() {
        let now = instant(2026, 8, 8, 21)
        let cal = calendar(losAngeles)

        XCTAssertEqual(DueDateLabel.dayHeading(for: instant(2026, 8, 8, 10), now: now, localCalendar: cal),
                       NSLocalizedString("time.today", comment: ""))
        XCTAssertEqual(DueDateLabel.dayHeading(for: instant(2026, 8, 7, 10), now: now, localCalendar: cal),
                       NSLocalizedString("time.yesterday", comment: ""))
    }

    func testAChatHeadingNeverSaysTomorrow() {
        // A message cannot arrive from tomorrow; clock skew saying so would be worse than a date.
        let now = instant(2026, 8, 8, 21)
        let heading = DueDateLabel.dayHeading(for: instant(2026, 8, 9, 10), now: now,
                                              localCalendar: calendar(losAngeles))

        XCTAssertNotEqual(heading, NSLocalizedString("time.tomorrow", comment: ""))
    }

    func testAChatTimestampShowsTimeTodayAndYesterdayBeforeThat() {
        let now = instant(2026, 8, 8, 21)
        let cal = calendar(losAngeles)

        let today = DueDateLabel.timestamp(for: instant(2026, 8, 8, 14, 30), now: now, localCalendar: cal)
        XCTAssertFalse(today.isEmpty)
        XCTAssertFalse(today.contains("Aug"), "a message from today shows only its time")

        XCTAssertEqual(DueDateLabel.timestamp(for: instant(2026, 8, 7, 14), now: now, localCalendar: cal),
                       NSLocalizedString("time.yesterday", comment: ""))

        let older = DueDateLabel.timestamp(for: instant(2026, 8, 1, 14), now: now, localCalendar: cal)
        XCTAssertNotEqual(older, NSLocalizedString("time.yesterday", comment: ""))
        XCTAssertFalse(older.isEmpty)
    }

    // MARK: - The guard: nobody hand-rolls these three words again

    func testNoSurfaceHardcodesTheDayNames() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        let audited = [
            "Astrid App/Views/Components/CompactTaskRow.swift",
            "Astrid App/Views/Tasks/TaskRowView.swift",
            "Astrid App/Views/Chat/ChatMessageListView.swift",
            "Astrid App/Views/Chat/ChatMessageBubble.swift",
            "Astrid Mac/Views/MacTaskRow.swift",
            "Astrid Mac/App/MacQuickAddPreview.swift",
        ]

        for relative in audited {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)

            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }

                for literal in ["\"Today\"", "\"Tomorrow\"", "\"Yesterday\""] {
                    XCTAssertFalse(code.contains(literal),
                                   "\(relative):\(index + 1) writes \(literal) as an English literal — "
                                   + "route it through DueDateLabel, which is localized and "
                                   + "handles all-day dates (AITD-317)")
                }
                XCTAssertFalse(code.contains("isDateInToday") || code.contains("isDateInYesterday"),
                               "\(relative):\(index + 1) re-implements the day comparison — "
                               + "it is wrong for all-day dates west of UTC (AITD-317)")
            }
        }
    }
}
