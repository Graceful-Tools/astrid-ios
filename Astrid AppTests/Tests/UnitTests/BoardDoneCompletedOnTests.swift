import XCTest
@testable import Astrid_App

/// A Done card shows when it was finished, as a pill under its title (Jon, 2026-11-19: "show the
/// completed date under the title as a pill… consistent on all platforms"). The same stamp
/// astrid-core sorts Done by, newest on top, and sends other clients as `completedOn`.
final class BoardDoneCompletedOnTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testThisYearIsMonthAndDay_doneDatePill() {
        let label = CompletedOnLabel.text(for: at("2026-11-19T15:00:00Z"), now: at("2026-11-20T09:00:00Z"),
                                          calendar: utc, locale: en)
        XCTAssertEqual(label, "Nov 19")
    }

    func testAnotherYearAddsTheYear_doneDatePill() {
        let label = CompletedOnLabel.text(for: at("2025-11-19T15:00:00Z"), now: at("2026-11-20T09:00:00Z"),
                                          calendar: utc, locale: en)
        XCTAssertEqual(label, "Nov 19, 2025")
    }

    func testTheDayIsTheReadersDay_doneDatePill() {
        var pacific = utc
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 03:00 UTC on the 19th is the evening of the 18th in California.
        let label = CompletedOnLabel.text(for: at("2026-11-19T03:00:00Z"), now: at("2026-11-20T09:00:00Z"),
                                          calendar: pacific, locale: en)
        XCTAssertEqual(label, "Nov 18")
    }

    func testCompletedAtWinsThenUpdatedAt_doneDatePill() {
        let stamped = Task(id: "a", title: "a", completed: true,
                           completedAt: at("2026-11-10T12:00:00Z"), updatedAt: at("2026-11-15T12:00:00Z"))
        XCTAssertEqual(CompletedOnLabel.completedAt(stamped), at("2026-11-10T12:00:00Z"))

        let legacy = Task(id: "b", title: "b", completed: true, updatedAt: at("2026-11-15T12:00:00Z"))
        XCTAssertEqual(CompletedOnLabel.completedAt(legacy), at("2026-11-15T12:00:00Z"))
    }

    func testAnOpenTaskHasNoPill_doneDatePill() {
        let open = Task(id: "c", title: "c", completedAt: at("2026-11-10T12:00:00Z"))
        XCTAssertNil(CompletedOnLabel.text(for: open))
    }
}
