import XCTest
@testable import Astrid_App

/// The wire shape of a list's completion window. Which completed tasks the window keeps is the
/// core's rule (AITD-460), pinned by astrid-core's `filters.json` contract and, on this side, by
/// `RecentlyCompletedPresetsTests` through `CoreRowsFixture`; the Swift copy of that rule had no
/// caller and went with its tests (AITD-532).
final class RecentlyCompletedWindowTests: XCTestCase {

    // MARK: - Codable round-trip

    func testCodableRoundTrip_duration_day() throws {
        let value = RecentlyCompletedWindow.duration(amount: 7, unit: .day)
        let data = try JSONEncoder().encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"duration\""))
        XCTAssertTrue(json.contains("\"amount\":7"))
        XCTAssertTrue(json.contains("\"unit\":\"day\""))
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testCodableRoundTrip_sinceWeekday() throws {
        let value = RecentlyCompletedWindow.sinceWeekday(weekday: 1) // Monday
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testCodableRoundTrip_sinceDayOfMonth() throws {
        let value = RecentlyCompletedWindow.sinceDayOfMonth(day: 15)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testCodableRoundTrip_sinceDate() throws {
        let value = RecentlyCompletedWindow.sinceDate(date: "2026-04-01")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testDecode_unknownKindThrows() {
        let json = "{\"kind\":\"bogus\"}".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RecentlyCompletedWindow.self, from: json))
    }
}
