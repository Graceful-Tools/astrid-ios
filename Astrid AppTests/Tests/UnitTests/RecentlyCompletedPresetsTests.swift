import XCTest
@testable import Astrid_App

/// Swift port of `tests/lib/recently-completed-presets.test.ts` (7
/// cases). Mirrors the web's preset list + lookup helpers so the list
/// admin picker behaves identically on both platforms.
final class RecentlyCompletedPresetsTests: XCTestCase {

    func test_exposesLabeledPresets_inStableOrder_defaultFirst() {
        let ids = RECENTLY_COMPLETED_PRESETS.map { $0.id }
        XCTAssertEqual(ids.first, .default24h)
        XCTAssertTrue(ids.contains(.last7Days))
        XCTAssertTrue(ids.contains(.last14Days))
        XCTAssertTrue(ids.contains(.last28Days))
        XCTAssertTrue(ids.contains(.last30Days))
        XCTAssertTrue(ids.contains(.sinceLastSunday))
        XCTAssertTrue(ids.contains(.sinceLastMonday))
        XCTAssertTrue(ids.contains(.sinceFirstOfMonth))
        XCTAssertTrue(ids.contains(.sinceSpecificDate))
    }

    func test_everyPresetHasHumanReadableLabel() {
        for preset in RECENTLY_COMPLETED_PRESETS {
            XCTAssertGreaterThan(preset.label.count, 2)
        }
    }

    func test_findPresetForWindow_nil_returnsDefault24h() {
        XCTAssertEqual(findPresetForWindow(nil)?.id, .default24h)
    }

    func test_findPresetForWindow_matchesDurationWindowsToRightPreset() {
        XCTAssertEqual(findPresetForWindow(.duration(amount: 7, unit: .day))?.id, .last7Days)
        XCTAssertEqual(findPresetForWindow(.duration(amount: 14, unit: .day))?.id, .last14Days)
        XCTAssertEqual(findPresetForWindow(.duration(amount: 28, unit: .day))?.id, .last28Days)
        XCTAssertEqual(findPresetForWindow(.duration(amount: 30, unit: .day))?.id, .last30Days)
    }

    func test_findPresetForWindow_matchesWeekday_dayOfMonth_specificDate() {
        XCTAssertEqual(findPresetForWindow(.sinceWeekday(weekday: 0))?.id, .sinceLastSunday)
        XCTAssertEqual(findPresetForWindow(.sinceWeekday(weekday: 1))?.id, .sinceLastMonday)
        XCTAssertEqual(findPresetForWindow(.sinceDayOfMonth(day: 1))?.id, .sinceFirstOfMonth)
        XCTAssertEqual(findPresetForWindow(.sinceDate(date: "2026-04-01"))?.id, .sinceSpecificDate)
    }

    func test_presetForValue_isInverse_defaultReturnsNil() {
        XCTAssertNil(presetForValue(.default24h))
        XCTAssertEqual(presetForValue(.last7Days), .duration(amount: 7, unit: .day))
        XCTAssertEqual(presetForValue(.sinceLastMonday), .sinceWeekday(weekday: 1))
        XCTAssertEqual(presetForValue(.sinceFirstOfMonth), .sinceDayOfMonth(day: 1))
    }

    func test_presetForValue_sinceSpecificDate_returnsNil_soCallerPromptsForDate() {
        XCTAssertNil(presetForValue(.sinceSpecificDate))
    }

    // MARK: - applyCompletionFilterWithWindow (bug 2026-05-12 #4)

    /// iOS's filter was hardcoded to 24 hours and ignored
    /// `list.recentlyCompletedWindow`. The web honored it. Result: a
    /// list with `Last 7 days` set on the web showed tasks the user
    /// didn't see on iOS. This test pins the fix.
    private func makeTask(id: String, completed: Bool, updatedAt: Date) -> Task {
        Task(
            id: id, title: id, description: "",
            isAllDay: false, priority: .none,
            isPrivate: false, completed: completed,
            updatedAt: updatedAt
        )
    }

    func test_default_withSevenDayWindow_keepsCompletedFromThreeDaysAgo() {
        let now = ISO8601DateFormatter().date(from: "2026-05-11T12:00:00Z")!
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let completed3d = makeTask(id: "c-3d", completed: true, updatedAt: threeDaysAgo)
        let incomplete = makeTask(id: "i", completed: false, updatedAt: threeDaysAgo)

        let result = applyCompletionFilterWithWindow(
            [completed3d, incomplete],
            filter: "default",
            window: .duration(amount: 7, unit: .day),
            now: now
        )
        XCTAssertEqual(Set(result.map { $0.id }), Set(["c-3d", "i"]),
                       "7-day window must include a task completed 3 days ago")
    }

    func test_default_withNilWindow_hidesCompletedOlderThan24h() {
        let now = ISO8601DateFormatter().date(from: "2026-05-11T12:00:00Z")!
        let twoDaysAgo = now.addingTimeInterval(-48 * 60 * 60)
        let oneHourAgo = now.addingTimeInterval(-60 * 60)
        let stale = makeTask(id: "stale", completed: true, updatedAt: twoDaysAgo)
        let fresh = makeTask(id: "fresh", completed: true, updatedAt: oneHourAgo)
        let incomplete = makeTask(id: "i", completed: false, updatedAt: twoDaysAgo)

        let result = applyCompletionFilterWithWindow(
            [stale, fresh, incomplete],
            filter: "default",
            window: nil,
            now: now
        )
        XCTAssertEqual(Set(result.map { $0.id }), Set(["fresh", "i"]),
                       "nil window = legacy 24h default: 2-day-old completion is hidden")
    }

    func test_all_returnsEverything() {
        let now = Date()
        let result = applyCompletionFilterWithWindow(
            [makeTask(id: "x", completed: true, updatedAt: now.addingTimeInterval(-365 * 86400))],
            filter: "all",
            window: nil,
            now: now
        )
        XCTAssertEqual(result.count, 1)
    }

    /// Regression lock for the "My Tasks flickers during Google backfill" bug:
    /// a backfilled import is completed YEARS ago (backdated completedAt) but
    /// its row was written just now (updatedAt = now). The default window must
    /// key on completedAt so history imports stay invisible — the old
    /// updatedAt-based copy in TaskListView made hundreds of them insert above
    /// the viewport while the backfill drained.
    func test_default_backfilledImport_oldCompletedAt_freshUpdatedAt_isHidden() {
        let now = ISO8601DateFormatter().date(from: "2026-07-04T12:00:00Z")!
        var backfilled = makeTask(id: "backfill", completed: true, updatedAt: now)
        backfilled.completedAt = ISO8601DateFormatter().date(from: "2010-10-26T01:23:55Z")!
        var justDone = makeTask(id: "fresh", completed: true, updatedAt: now)
        justDone.completedAt = now.addingTimeInterval(-3600)

        let visible = applyCompletionFilterWithWindow(
            [backfilled, justDone], filter: "default", window: nil, now: now)
        XCTAssertEqual(visible.map { $0.id }, ["fresh"],
                       "backdated history must be hidden; a task completed an hour ago must show")
    }

    func test_completed_andIncomplete_useStrictFilter() {
        let now = Date()
        let c = makeTask(id: "c", completed: true, updatedAt: now)
        let i = makeTask(id: "i", completed: false, updatedAt: now)
        XCTAssertEqual(applyCompletionFilterWithWindow([c, i], filter: "completed", window: nil, now: now).map { $0.id }, ["c"])
        XCTAssertEqual(applyCompletionFilterWithWindow([c, i], filter: "incomplete", window: nil, now: now).map { $0.id }, ["i"])
    }
}
