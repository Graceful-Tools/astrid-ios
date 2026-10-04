//  DueDateQuickPicksTests.swift
//  Task ea4f5124 — "[mac] fix task details / date / time / repeat picker to look and work more
//  like iOS."
//
//  The Mac detail offered a bare DatePicker and a bare repeat Picker: no Today/Tomorrow, no
//  Morning/Afternoon/Evening, no "No due date" as a choice. iOS had all of it — in private
//  arrays inside InlineDatePicker and InlineTimePicker, where the Mac could not reach them.
//
//  Retyping those lists on the Mac is how two platforms come to disagree about what "Next week"
//  means. Since AITD-461 both ask astrid-core's `dueDateOptions` (`DuePicks`), and these run
//  against a seeded in-memory core: the same options, in the same order, each meaning the date
//  iOS's picker always wrote (CONTRACTS D48). Day arithmetic across a daylight-saving change is
//  pinned in the core (`adding_a_day_moves_the_calendar_day_not_a_fixed_number_of_seconds`).

import XCTest
@testable import Astrid_App

final class DueDateQuickPicksTests: XCTestCase {

    private func picks(_ date: Date?, isAllDay: Bool) throws -> DueOptions {
        let session = try CoreBoardFixture.session(lists: [], projects: [])
        return try CoreRowsFixture.wait(session, DuePicks.command(date, isAllDay: isAllDay), as: DueOptions.self)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - The option sets are the contract

    /// The four date picks iOS has always shipped, in order.
    func testDateOptionsMatchWhatIOSOffers() throws {
        let options = try picks(nil, isAllDay: true)
        XCTAssertEqual(options.dates.map(\.daysFromToday), [0, 1, 3, 7])
        XCTAssertEqual(options.dates.map(\.titleKey),
                       ["picker.today", "picker.tomorrow", "picker.in_3_days", "picker.next_week"])
    }

    /// And the four times, with the hours the labels promise.
    func testTimeOptionsMatchWhatIOSOffers() throws {
        let options = try picks(nil, isAllDay: true)
        XCTAssertEqual(options.times.map(\.hour), [9, 14, 18, 21])
        XCTAssertEqual(options.times.map(\.titleKey),
                       ["picker.morning", "picker.afternoon", "picker.evening", "picker.night"])
    }

    /// Titles are localisation keys, never literals — these reach the screen on both platforms
    /// and Astrid ships 12 languages.
    func testEveryOptionTitleIsALocalisationKey() throws {
        let options = try picks(nil, isAllDay: true)
        let titles = options.dates.map(\.titleKey) + options.times.map(\.titleKey)
        XCTAssertTrue(titles.allSatisfy { $0.hasPrefix("picker.") && NSLocalizedString($0, comment: "") != $0 },
                      "a literal, or a key iOS lacks, would ship untranslated on both platforms")
    }

    // MARK: - What a date pick means

    /// Today is the reader's calendar day, stored as an all-day date at UTC midnight — 4pm PT on
    /// Nov 22 is the 22nd, not the 23rd it already is in UTC.
    func testTodayIsTheReadersDayAtUTCMidnight() throws {
        let pick = try XCTUnwrap(try picks(nil, isAllDay: true).dates.first?.date)
        let local = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let stored = utc.dateComponents([.year, .month, .day, .hour, .minute], from: pick)
        XCTAssertEqual([stored.year, stored.month, stored.day], [local.year, local.month, local.day])
        XCTAssertEqual([stored.hour, stored.minute], [0, 0])
    }

    func testTomorrowIsTheNextCalendarDay() throws {
        let pick = try XCTUnwrap(try picks(nil, isAllDay: true).dates[1].date)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let local = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        let stored = utc.dateComponents([.year, .month, .day], from: pick)
        XCTAssertEqual([stored.year, stored.month, stored.day], [local.year, local.month, local.day])
    }

    /// D48 (AITD-461): a date pick on a TIMED task makes it all-day that day, as iOS's picker
    /// always wrote it (`setQuickDate` → `updateTask(when:)`). The core kept the time; iOS won.
    func testADatePickOnATimedTaskIsAnAllDayDate() throws {
        let timed = Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: Date())!
        let pick = try picks(timed, isAllDay: false).dates[3]
        let stored = utc.dateComponents([.hour, .minute], from: try XCTUnwrap(pick.date))
        XCTAssertEqual([stored.hour, stored.minute], [0, 0])
        XCTAssertTrue(try picks(timed, isAllDay: false).dates[0].isSelected, "due today: Today is lit")
    }

    // MARK: - What a time pick means

    /// "Morning" means 9:00 exactly, on the task's own day.
    func testChoosingATimeZeroesTheMinutesAndKeepsTheDay() throws {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 5, to: calendar.date(bySettingHour: 3, minute: 37, second: 44, of: Date())!)!
        let morning = try XCTUnwrap(try picks(day, isAllDay: false).times[0].date)
        XCTAssertEqual(calendar.component(.hour, from: morning), 9)
        XCTAssertEqual(calendar.component(.minute, from: morning), 0)
        XCTAssertTrue(calendar.isDate(morning, inSameDayAs: day))
    }

    /// D48: an all-day task's time goes on ITS date — the local reading of its UTC midnight is the
    /// day before anywhere west of UTC.
    func testATimeOnAnAllDayTaskLandsOnItsDate() throws {
        let allDay = utc.date(from: DateComponents(year: 2030, month: 6, day: 10))!
        let evening = try XCTUnwrap(try picks(allDay, isAllDay: true).times[2].date)
        let local = Calendar.current.dateComponents([.year, .month, .day, .hour], from: evening)
        XCTAssertEqual([local.year, local.month, local.day, local.hour], [2030, 6, 10, 18])
    }
}
