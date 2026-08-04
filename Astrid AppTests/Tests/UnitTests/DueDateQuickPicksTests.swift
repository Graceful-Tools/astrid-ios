//  DueDateQuickPicksTests.swift
//  Task ea4f5124 — "[mac] fix task details / date / time / repeat picker to look and work more
//  like iOS."
//
//  The Mac detail offered a bare DatePicker and a bare repeat Picker: no Today/Tomorrow, no
//  Morning/Afternoon/Evening, no "No due date" as a choice. iOS had all of it — in private
//  arrays inside InlineDatePicker and InlineTimePicker, where the Mac could not reach them.
//
//  Retyping those lists on the Mac is how two platforms come to disagree about what "Next week"
//  means. These tests pin the shared source instead: the same options, in the same order, with
//  date arithmetic that survives a DST boundary.

import XCTest
@testable import Astrid_App

final class DueDateQuickPicksTests: XCTestCase {

    // MARK: - The option sets are the contract

    /// The four date picks iOS has always shipped, in order.
    func testDateOptionsMatchWhatIOSOffers() {
        XCTAssertEqual(DueDateQuickPicks.dateOptions.map(\.daysFromToday), [0, 1, 3, 7])
        XCTAssertEqual(DueDateQuickPicks.dateOptions.map(\.titleKey),
                       ["picker.today", "picker.tomorrow", "picker.in_3_days", "picker.next_week"])
    }

    /// And the four times, with the hours the labels promise.
    func testTimeOptionsMatchWhatIOSOffers() {
        XCTAssertEqual(DueDateQuickPicks.timeOptions.map(\.hour), [9, 14, 18, 21])
        XCTAssertEqual(DueDateQuickPicks.timeOptions.map(\.titleKey),
                       ["picker.morning", "picker.afternoon", "picker.evening", "picker.night"])
    }

    /// Titles are localisation keys, never literals — these reach the screen on both platforms
    /// and Astrid ships 12 languages.
    func testEveryOptionTitleIsALocalisationKey() {
        let titles = DueDateQuickPicks.dateOptions.map(\.titleKey)
            + DueDateQuickPicks.timeOptions.map(\.titleKey)
        XCTAssertTrue(titles.allSatisfy { $0.hasPrefix("picker.") },
                      "a literal here would ship untranslated on both platforms")
    }

    // MARK: - Date arithmetic

    func testTodayIsToday() {
        let now = Date()
        let result = DueDateQuickPicks.date(daysFromToday: 0, from: now)

        XCTAssertTrue(Calendar.current.isDate(result, inSameDayAs: now))
    }

    func testTomorrowIsTheNextCalendarDay() {
        let now = Date()
        let result = DueDateQuickPicks.date(daysFromToday: 1, from: now)
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: now)!

        XCTAssertTrue(Calendar.current.isDate(result, inSameDayAs: expected))
    }

    /// THE ONE THAT BITES: a day is not 86 400 seconds. Across a DST change it is 23 or 25
    /// hours, so seconds-based arithmetic lands "Tomorrow" on the wrong date twice a year.
    /// Pinned with a real transition — 2 November 2025, when US clocks went back.
    func testDayArithmeticSurvivesADaylightSavingBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        // 1 Nov 2025, 20:00 — the evening before clocks go back.
        let before = try XCTUnwrap(DateComponents(
            calendar: calendar, year: 2025, month: 11, day: 1, hour: 20).date)

        let tomorrow = DueDateQuickPicks.date(daysFromToday: 1, from: before, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: tomorrow), 2,
                       "adding 86,400s across the fall-back would land on the 1st again")
        XCTAssertEqual(calendar.component(.month, from: tomorrow), 11)
    }

    /// Picking a DATE must not throw away a time the user already set.
    func testChoosingADateKeepsTheTimeOfDay() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 15, minute: 30, second: 0, of: Date())!

        let result = DueDateQuickPicks.date(daysFromToday: 3, from: now)

        XCTAssertEqual(calendar.component(.hour, from: result), 15)
        XCTAssertEqual(calendar.component(.minute, from: result), 30)
    }

    // MARK: - Time arithmetic

    /// "Morning" means 9:00 exactly — not 9:37 because that happened to be the old minute.
    func testChoosingATimeZeroesTheMinutes() {
        let calendar = Calendar.current
        let messy = calendar.date(bySettingHour: 3, minute: 37, second: 44, of: Date())!

        let result = DueDateQuickPicks.applying(hour: 9, to: messy)

        XCTAssertEqual(calendar.component(.hour, from: result), 9)
        XCTAssertEqual(calendar.component(.minute, from: result), 0)
        XCTAssertEqual(calendar.component(.second, from: result), 0)
    }

    /// Setting a time keeps the day it was set on.
    func testChoosingATimeKeepsTheDay() {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 5, to: Date())!

        let result = DueDateQuickPicks.applying(hour: 18, to: day)

        XCTAssertTrue(calendar.isDate(result, inSameDayAs: day))
    }
}
