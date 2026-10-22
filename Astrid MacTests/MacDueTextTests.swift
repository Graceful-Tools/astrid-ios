//  MacDueTextTests.swift
//  AITD-520 — "[mac] make sure we use shorter date formats in list rows / board views (e.g. Oct. 3,
//  2027) vs October 3, 2027". The list row already used the shared row format; the board card drew
//  `Text(date, style: .date)`, which is the LONG style, and read an all-day date — stored at
//  midnight UTC — in the user's zone, so west of UTC the card showed the day before.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacDueTextTests: XCTestCase {

    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private var laCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        return calendar
    }

    private var now: Date {
        laCalendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
    }

    /// Midnight UTC on 3 October 2027 — how an all-day task is stored.
    private var allDayOct3: Date {
        DateFormatterCache.utcCalendar.date(from: DateComponents(year: 2027, month: 10, day: 3))!
    }

    func testAITD520_aFarOffDateIsTheMediumFormatNotTheLongOne() {
        let text = MacDueText.text(for: allDayOct3, isAllDay: true, now: now, localCalendar: laCalendar)

        let long = DateFormatterCache.formatter(.styles(date: .long, time: .none),
                                                timeZone: TimeZone(identifier: "UTC"))
            .string(from: allDayOct3)
        let medium = DateFormatterCache.formatter(.styles(date: .medium, time: .none),
                                                  timeZone: TimeZone(identifier: "UTC"))
            .string(from: allDayOct3)

        XCTAssertNotEqual(text, long, "\"October 3, 2027\" is the long style the card used to draw")
        XCTAssertEqual(text, medium, "an all-day date reads its stored day, in the short row format")
    }

    func testAITD520_theCardAndTheRowSayTheSameThing() {
        let timed = laCalendar.date(from: DateComponents(year: 2027, month: 10, day: 3, hour: 15))!
        XCTAssertEqual(MacDueText.text(for: timed, isAllDay: false, now: now, localCalendar: laCalendar),
                       DueDateLabel.rowMediumText(for: timed, isAllDay: false, now: now,
                                                  localCalendar: laCalendar))
    }

    func testAITD520_aNamedDayStaysNamed() {
        let tomorrow = DateFormatterCache.utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        XCTAssertEqual(MacDueText.text(for: tomorrow, isAllDay: true, now: now, localCalendar: laCalendar),
                       NSLocalizedString("time.tomorrow", comment: "Tomorrow"))
    }

    func testNoDateNoText() {
        XCTAssertNil(MacDueText.text(for: nil, isAllDay: false))
    }
}
#endif
