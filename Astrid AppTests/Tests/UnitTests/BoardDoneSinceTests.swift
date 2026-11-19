import XCTest
@testable import Astrid_App

/// ADEV-131: the Done column counts what was finished SINCE a period start — "Done · 15 ✓ This
/// week" — chosen per list and per person, on every platform. A week is Monday–Sunday whatever the
/// locale's first weekday; presets roll with the clock, a picked date stays put.
final class BoardDoneSinceTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1   // a Sunday-first locale: the week must still start on Monday
        return calendar
    }
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    /// Thursday 19 November 2026, mid-afternoon.
    private var now: Date { at("2026-11-19T15:00:00Z") }

    func testPeriodStarts_ADEV131() {
        XCTAssertEqual(DoneSince.today.start(now: now, calendar: utc), at("2026-11-19T00:00:00Z"))
        XCTAssertEqual(DoneSince.thisWeek.start(now: now, calendar: utc), at("2026-11-16T00:00:00Z"))
        XCTAssertEqual(DoneSince.thisMonth.start(now: now, calendar: utc), at("2026-11-01T00:00:00Z"))
        XCTAssertEqual(DoneSince.thisYear.start(now: now, calendar: utc), at("2026-01-01T00:00:00Z"))
        XCTAssertEqual(DoneSince.date(at("2026-11-01T18:30:00Z")).start(now: now, calendar: utc),
                       at("2026-11-01T00:00:00Z"))
        XCTAssertNil(DoneSince.all.start(now: now, calendar: utc))
    }

    func testSundayBelongsToTheWeekThatStartedMonday_ADEV131() {
        let sunday = at("2026-11-22T20:00:00Z")
        XCTAssertEqual(DoneSince.thisWeek.start(now: sunday, calendar: utc), at("2026-11-16T00:00:00Z"))
    }

    func testFilterKeepsWhatWasFinishedSinceTheStart_ADEV131() {
        let thisWeek = Task(id: "a", title: "a", completed: true, completedAt: at("2026-11-17T09:00:00Z"))
        let lastWeek = Task(id: "b", title: "b", completed: true, completedAt: at("2026-11-13T09:00:00Z"))
        let legacy = Task(id: "c", title: "c", completed: true, updatedAt: at("2026-11-18T09:00:00Z"))
        let open = Task(id: "d", title: "d", completedAt: at("2026-11-18T09:00:00Z"))
        let kept = DoneSince.thisWeek.filter([thisWeek, lastWeek, legacy, open], now: now, calendar: utc)
        XCTAssertEqual(kept.map(\.id), ["a", "c"])
        XCTAssertEqual(DoneSince.all.filter([thisWeek, lastWeek], now: now, calendar: utc).count, 2)
    }

    func testLabels_ADEV131() {
        XCTAssertEqual(DoneSince.date(at("2026-11-01T12:00:00Z")).label(now: now, calendar: utc, locale: en),
                       "since Sun, Nov 1")
        XCTAssertEqual(DoneSince.date(at("2025-11-01T12:00:00Z")).label(now: now, calendar: utc, locale: en),
                       "since Sat, Nov 1, 2025")
        XCTAssertFalse(DoneSince.thisWeek.label(now: now, calendar: utc, locale: en).isEmpty)
        XCTAssertEqual(DoneSince.headerText(count: 15, label: "This week"), "15 ✓ This week")
    }

    func testSavedPerListAndPerPerson_ADEV131() {
        let defaults = UserDefaults(suiteName: "BoardDoneSinceTests")!
        defaults.removePersistentDomain(forName: "BoardDoneSinceTests")
        XCTAssertEqual(DoneSince.load(listId: "L1", userId: "u1", defaults: defaults), .thisWeek)

        DoneSince.thisYear.save(listId: "L1", userId: "u1", defaults: defaults)
        DoneSince.date(at("2026-11-01T00:00:00Z")).save(listId: "L2", userId: "u1", defaults: defaults)
        XCTAssertEqual(DoneSince.load(listId: "L1", userId: "u1", defaults: defaults), .thisYear)
        XCTAssertEqual(DoneSince.load(listId: "L2", userId: "u1", defaults: defaults),
                       .date(at("2026-11-01T00:00:00Z")))
        XCTAssertEqual(DoneSince.load(listId: "L1", userId: "u2", defaults: defaults), .thisWeek)
        DoneSince.all.save(listId: "L1", userId: "u2", defaults: defaults)
        XCTAssertEqual(DoneSince.load(listId: "L1", userId: "u2", defaults: defaults), .all)
    }
}
