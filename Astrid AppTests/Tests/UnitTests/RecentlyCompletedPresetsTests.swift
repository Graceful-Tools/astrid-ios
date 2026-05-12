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
}
