//  TimerDurationMemoryTests.swift
//  Regression tests for AITD-593 — "New timer should remain at what they were last set at.
//  Currently they are resetting to 25 minutes!"
//
//  A task that has never been timed has no `timerDuration`, and the timer screen used to open
//  those at a hardcoded 25 minutes whatever the user had just picked on the last one.

import XCTest
@testable import Astrid_App

final class TimerDurationMemoryTests: XCTestCase {

    /// A UserDefaults nobody else is using, unique per call so parallel clones cannot share it.
    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "TimerDurationMemoryTests.\(name).\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    func testAITD593_aNewTimerStartsAtTheDurationLastSet() {
        let memory = TimerDurationMemory(defaults: scratchDefaults())
        memory.remember(40)

        XCTAssertEqual(memory.initialDuration(for: nil), 40)
        XCTAssertEqual(memory.initialDuration(for: 0), 40)
    }

    func testAITD593_theLastSetDurationSurvivesARelaunch() {
        let defaults = scratchDefaults()
        TimerDurationMemory(defaults: defaults).remember(15)

        XCTAssertEqual(TimerDurationMemory(defaults: defaults).initialDuration(for: nil), 15)
    }

    func testAITD593_aTaskThatWasTimedKeepsItsOwnDuration() {
        let memory = TimerDurationMemory(defaults: scratchDefaults())
        memory.remember(40)

        XCTAssertEqual(memory.initialDuration(for: 10), 10)
    }

    /// The Mac's count-up timer accumulates on the same field, so a task can carry a total the
    /// countdown picker (1...120) cannot show; that is not a countdown length to start from.
    func testAITD593_aSavedDurationOutsideThePickerFallsBackToTheLastSet() {
        let memory = TimerDurationMemory(defaults: scratchDefaults())
        memory.remember(20)

        XCTAssertEqual(memory.initialDuration(for: 3600), 20)
    }

    func testAITD593_withNothingRememberedItIsTwentyFiveMinutes() {
        let memory = TimerDurationMemory(defaults: scratchDefaults())

        XCTAssertEqual(memory.initialDuration(for: nil), 25)
    }

    func testAITD593_aDurationThePickerCannotShowIsNotRemembered() {
        let memory = TimerDurationMemory(defaults: scratchDefaults())
        memory.remember(30)
        memory.remember(0)
        memory.remember(500)

        XCTAssertEqual(memory.initialDuration(for: nil), 30)
    }
}
