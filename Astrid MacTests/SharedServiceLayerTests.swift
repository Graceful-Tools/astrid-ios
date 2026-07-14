//  SharedServiceLayerTests.swift
//  Astrid for Mac — proves the SHARED service/logic layer runs on macOS (not just compiles).
//
//  Exercises RepeatingTaskCalculator, the cross-platform repeating-task contract that mirrors
//  astrid-web/types/repeating.ts. If this passes on the macOS destination, the shared Core that
//  the iOS app uses is genuinely running on Mac.

import XCTest
@testable import Astrid_Mac

final class SharedServiceLayerTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 30) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testDailyRepeatRollsOverOnMac() {
        let due = date(2024, 1, 15)
        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .daily,
            currentDueDate: due,
            completionDate: date(2024, 1, 15, 14, 0),
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )
        XCTAssertNotNil(result.nextDueDate)
        XCTAssertFalse(result.shouldTerminate)
        XCTAssertEqual(result.newOccurrenceCount, 1)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.day, from: result.nextDueDate!), 16, "daily → next day")
        XCTAssertEqual(cal.component(.hour, from: result.nextDueDate!), 10, "preserves due time")
        XCTAssertEqual(cal.component(.minute, from: result.nextDueDate!), 30)
    }

    func testWeeklyRepeatRollsOverOnMac() {
        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: .weekly,
            currentDueDate: date(2024, 1, 15),
            completionDate: date(2024, 1, 15, 14, 0),
            repeatFrom: .DUE_DATE,
            currentOccurrenceCount: 0
        )
        XCTAssertNotNil(result.nextDueDate)
        XCTAssertEqual(Calendar.current.component(.day, from: result.nextDueDate!), 22, "weekly → +7 days")
    }

    func testMultiStepDailyProgressionOnMac() {
        var due: Date? = date(2024, 1, 15)
        var count = 0
        for _ in 0..<5 {
            let r = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
                repeatingType: .daily,
                currentDueDate: due,
                completionDate: due!,
                repeatFrom: .DUE_DATE,
                currentOccurrenceCount: count
            )
            due = r.nextDueDate
            count = r.newOccurrenceCount
        }
        XCTAssertEqual(count, 5)
        // 5 daily steps from Jan 15 → Jan 20.
        XCTAssertEqual(Calendar.current.component(.day, from: due!), 20)
    }
}
