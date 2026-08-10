//  MacDateEntryTests.swift
//  Typing a date into the Mac date popover.
//
//  Two failed attempts preceded this. `.field` gives a typable control but drags
//  the system's own small calendar overlay in on top of ours — two calendars at
//  once. `.graphical` gives a calendar that can be sized and centred but cannot
//  be typed into at all, which is what got reported.
//
//  So the typing is ours, and therefore testable: what someone types either
//  becomes the date they meant or is refused. A wrong date silently accepted is
//  worse than a field that declines to change.

import XCTest
@testable import Astrid_Mac

final class MacDateEntryTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US")

    private func day(_ date: Date?) -> DateComponents? {
        guard let date else { return nil }
        return Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: date)
    }

    // MARK: - What people actually type

    func testParsesTheLocaleShortForm() {
        let parsed = day(MacDateEntry.parse("8/12/2026", locale: enUS))
        XCTAssertEqual(parsed?.year, 2026)
        XCTAssertEqual(parsed?.month, 8)
        XCTAssertEqual(parsed?.day, 12)
    }

    /// A two-digit year is a thing people type and must not be refused.
    func testParsesATwoDigitYear() {
        XCTAssertEqual(day(MacDateEntry.parse("8/12/26", locale: enUS))?.year, 2026)
    }

    /// And the written form, which is what the chip shows them.
    func testParsesTheMediumForm() {
        let parsed = day(MacDateEntry.parse("Aug 12, 2026", locale: enUS))
        XCTAssertEqual(parsed?.month, 8)
        XCTAssertEqual(parsed?.day, 12)
    }

    /// Whatever `format` produces must parse back — otherwise the field shows a
    /// date it would then reject.
    func testWhatTheFieldShowsIsWhatTheFieldAccepts() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 12, day: 25))!
        let shown = MacDateEntry.format(date, locale: enUS)
        let parsed = day(MacDateEntry.parse(shown, locale: enUS))
        XCTAssertEqual(parsed?.year, 2026)
        XCTAssertEqual(parsed?.month, 12)
        XCTAssertEqual(parsed?.day, 25)
    }

    // MARK: - Refusing rather than guessing

    func testEmptyIsRefused() {
        XCTAssertNil(MacDateEntry.parse("", locale: enUS))
        XCTAssertNil(MacDateEntry.parse("   ", locale: enUS))
    }

    /// Nonsense must not become a date. Guessing here would silently move a
    /// task, which is the failure mode this whole area keeps producing.
    func testNonsenseIsRefused() {
        XCTAssertNil(MacDateEntry.parse("not a date", locale: enUS))
        XCTAssertNil(MacDateEntry.parse("??", locale: enUS))
    }

    /// Surrounding whitespace is the user's, not an error.
    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(day(MacDateEntry.parse("  8/12/2026  ", locale: enUS))?.day, 12)
    }

    /// The field order follows the LOCALE. Parsing 12/8 as December 8th for a
    /// British user would move the task four months.
    func testFieldOrderFollowsTheLocale() {
        let enGB = Locale(identifier: "en_GB")
        let parsed = day(MacDateEntry.parse("12/08/2026", locale: enGB))
        XCTAssertEqual(parsed?.month, 8, "en_GB writes day first")
        XCTAssertEqual(parsed?.day, 12)
    }
}
