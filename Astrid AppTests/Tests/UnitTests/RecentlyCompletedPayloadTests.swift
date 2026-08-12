//  RecentlyCompletedPayloadTests.swift
//  Regression guard for Task 545812e6 — found while auditing what Mac list settings were
//  missing against iOS.
//
//  iOS's admin tab has a "Recently completed window" picker, but `handleListUpdate`'s diff
//  builder had no branch for the field. Changing it updated the local model and was then
//  DROPPED before the request — the picker looked like it worked until the next fetch.
//
//  The payload shape lives on the model so both platforms send the same thing, and so it cannot
//  drift from `encode(to:)`, which is what reads it back.

import XCTest
@testable import Astrid_App

final class RecentlyCompletedPayloadTests: XCTestCase {

    /// The wire form must use the same kind strings the decoder accepts.
    func testEachWindowKindRoundTripsItsPayload() throws {
        let cases: [(RecentlyCompletedWindow, String)] = [
            (.duration(amount: 7, unit: .day), "duration"),
            (.sinceWeekday(weekday: 1), "since-weekday"),
            (.sinceDayOfMonth(day: 1), "since-day-of-month"),
            (.sinceDate(date: "2026-08-12"), "since-date"),
        ]
        for (window, kind) in cases {
            XCTAssertEqual(window.updatePayloadValue["kind"] as? String, kind)
        }
    }

    func testDurationCarriesAmountAndUnit() {
        let p = RecentlyCompletedWindow.duration(amount: 14, unit: .day).updatePayloadValue
        XCTAssertEqual(p["amount"] as? Int, 14)
        XCTAssertEqual(p["unit"] as? String, "day")
    }

    func testSinceDateCarriesTheDay() {
        XCTAssertEqual(RecentlyCompletedWindow.sinceDate(date: "2026-08-12")
            .updatePayloadValue["date"] as? String, "2026-08-12")
    }

    /// What the app writes must be what the app can read back — the two representations sitting
    /// next to each other is the only thing keeping them honest.
    func testThePayloadDecodesBackToTheSameWindow() throws {
        for window in [RecentlyCompletedWindow.duration(amount: 28, unit: .day),
                       .sinceWeekday(weekday: 0),
                       .sinceDayOfMonth(day: 1),
                       .sinceDate(date: "2026-01-31")] {
            let data = try JSONSerialization.data(withJSONObject: window.updatePayloadValue)
            XCTAssertEqual(try JSONDecoder().decode(RecentlyCompletedWindow.self, from: data), window)
        }
    }

    /// The bug itself: the field has to appear in the update the view actually sends.
    func testTheListUpdateDiffSendsTheWindow() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Views/Tasks/TaskListView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(#"updates["recentlyCompletedWindow"]"#),
                      "Changing the window must reach the server, not just the local model")
    }
}
