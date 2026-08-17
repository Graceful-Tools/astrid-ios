//  AppearanceTaskDisplayTests.swift
//  The Appearance control for the task-detail layout (task 96727335).
//
//  Jon: "add appearance setting to work with the task details option for people who have the
//  projects feature flipper turned on. implement in both iOS and mac."
//
//  TWO GATES THAT LOOK ALIKE AND ARE NOT. This task says to show the control only to people with
//  the projects flag on. Task 8ef7d89d says the preference itself must NOT be gated on that flag,
//  because `project_mode` is access ("may this user use projects at all") and `taskDisplayMode`
//  is a preference. Both are true at once: the CONTROL is gated, the BEHAVIOUR is not. Getting
//  that backwards would either hide the setting from people who set it on the web, or make a
//  stored "project" quietly stop working when a flag flips.
//
//  These are source guards because the pickers are SwiftUI views with no seam to instantiate
//  headlessly. The rules they protect are behavioural and are tested for real in
//  TaskDisplayModeTests; what is pinned here is that both platforms actually wire them up.

import XCTest
@testable import Astrid_App

final class AppearanceTaskDisplayTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private let iOSView = "Astrid App/Views/Settings/AppearanceSettingsView.swift"
    private let macView = "Astrid Mac/App/MacSettingsView.swift"

    // MARK: - Both platforms, as asked

    func testBothPlatformsOfferTheControl() throws {
        for path in [iOSView, macView] {
            let text = try source(path)
            XCTAssertTrue(text.contains("settings.task_display.list"), "\(path) is missing the picker")
            XCTAssertTrue(text.contains("settings.task_display.project"), "\(path) is missing the picker")
        }
    }

    /// Gated on the flag — the half this task asks for.
    func testBothPlatformsGateTheControlOnTheProjectsFlag() throws {
        for path in [iOSView, macView] {
            let text = try source(path)
            XCTAssertTrue(text.contains("featureFlags.isEnabled(.projectMode)"),
                          "\(path) must only offer this where projects are enabled")
        }
    }

    // MARK: - The stale-control trap, on both

    /// A picker that saves correctly but starts at the default re-saves the default over the
    /// user's choice the moment it is touched. Both platforms must refuse until settings load.
    func testNeitherPlatformCanSaveBeforeSettingsLoad() throws {
        for path in [iOSView, macView] {
            let text = try source(path)
            XCTAssertTrue(text.contains("mayPersistSelection"),
                          "\(path) must not write before settings have loaded")
            XCTAssertTrue(text.contains("hasLoadedFromServer"),
                          "\(path) must consult the real load signal, not the cache")
        }
    }

    // MARK: - Reads normalize, writes reject

    /// Read through the resolver so null and unknown land on `.list`, and write only the two
    /// literals — the server answers 400 to anything else.
    func testBothPlatformsReadThroughTheResolverAndWriteTheWireValue() throws {
        for path in [iOSView, macView] {
            let text = try source(path)
            XCTAssertTrue(text.contains("TaskDisplayMode(stored:"),
                          "\(path) must resolve null/unknown rather than compare the raw string")
            XCTAssertTrue(text.contains("wireValue"),
                          "\(path) must send only the literals the server accepts")
        }
    }

    // MARK: - The gate is on the control, never on the behaviour

    /// The distinction this task is most likely to lose. Nothing outside the settings screens may
    /// consult the projects flag to decide the LAYOUT.
    func testTheLayoutQuestionsAreNeverGatedOnTheFlag() throws {
        let mode = try source("Astrid App/Models/TaskDisplayMode.swift")
        XCTAssertFalse(mode.contains("FeatureFlagService"),
                       "taskDisplayMode is a preference; project_mode is access. Neither gates the other.")
    }

}
