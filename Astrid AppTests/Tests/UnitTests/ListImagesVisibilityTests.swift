//  ListImagesVisibilityTests.swift
//  The hide_list_images A/B test and the "Show list images" setting (AITD-468).
//
//  Web runs the experiment (astrid-web lib/list-images-visibility.ts). iOS and Mac read the same
//  two inputs so a user lands in the same arm on every device:
//
//   - `hide_list_images` from GET /api/v1/features
//   - `showListImages` (Bool?) from GET/PATCH /api/v1/users/me/smart-tasks
//
//  The rule is `showListImages ?? !hide_list_images`: null follows the flag, an explicit choice
//  always wins. The cases below are the ones that fail quietly — a dropped field reads as null,
//  and null silently hands the decision back to the experiment.

import XCTest
@testable import Astrid_App

final class ListImagesVisibilityTests: XCTestCase {

    // MARK: - The rule (mirrors shouldShowListImages on web)

    func testAITD468_NoPreferenceFollowsTheExperiment() {
        XCTAssertTrue(ListImagesVisibility.shouldShow(preference: nil, hideFlag: false))
        XCTAssertFalse(ListImagesVisibility.shouldShow(preference: nil, hideFlag: true))
    }

    func testAITD468_AnExplicitChoiceBeatsTheExperiment() {
        XCTAssertTrue(ListImagesVisibility.shouldShow(preference: true, hideFlag: true))
        XCTAssertFalse(ListImagesVisibility.shouldShow(preference: false, hideFlag: false))
    }

    // MARK: - The flag

    func testAITD468_HideListImagesIsTheServerKey() {
        XCTAssertEqual(AstridFeature.hideListImages.rawValue, "hide_list_images")
    }

    func testAITD468_ImagesShowUntilTheServerSaysOtherwise() {
        // A user with no cached flags (first launch, offline) keeps today's UI.
        let empty = FeatureFlagSnapshot(version: 0, features: [:], updatedAt: .distantPast)
        XCTAssertFalse(empty.isEnabled(.hideListImages))
        let hidden = FeatureFlagSnapshot(version: 1, features: ["hide_list_images": true], updatedAt: Date())
        XCTAssertTrue(hidden.isEnabled(.hideListImages))
    }

    // MARK: - The preference on the wire

    func testAITD468_SettingsDecodeWithoutTheField() throws {
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"subtaskDisplay":"indented"}"#.utf8))
        XCTAssertNil(settings.showListImages)
    }

    func testAITD468_SettingsDecodeNullAndExplicitValues() throws {
        let null = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"showListImages":null}"#.utf8))
        XCTAssertNil(null.showListImages)
        let off = try JSONDecoder().decode(UserSettings.self, from: Data(#"{"showListImages":false}"#.utf8))
        XCTAssertEqual(off.showListImages, false)
    }

    func testAITD468_DefaultSettingsLeaveTheChoiceToTheExperiment() {
        XCTAssertNil(UserSettings().showListImages)
    }

    func testAITD468_AnUnchosenPreferenceIsNeverSent() throws {
        // Sending a value the user never picked would end their part in the experiment.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(UserSettings())) as? [String: Any]
        XCTAssertNil(json?["showListImages"])
    }

    // MARK: - Writing the choice

    func testAITD468_TheChoiceSurvivesTheMerge() {
        let merged = UserSettings.merging(ListImagesVisibility.change(showListImages: false), into: UserSettings())
        XCTAssertEqual(merged.showListImages, false)
    }

    func testAITD468_TheChoiceTouchesNoOtherSetting() {
        let current = UserSettings(smartTaskCreationEnabled: false, emailToTaskEnabled: false,
                                   defaultTaskDueOffset: "none", defaultDueTime: "09:00",
                                   subtaskDisplay: "under_parent", taskDisplayMode: "project")
        let merged = UserSettings.merging(ListImagesVisibility.change(showListImages: true), into: current)
        XCTAssertEqual(merged.showListImages, true)
        XCTAssertEqual(merged.smartTaskCreationEnabled, false)
        XCTAssertEqual(merged.emailToTaskEnabled, false)
        XCTAssertEqual(merged.defaultTaskDueOffset, "none")
        XCTAssertEqual(merged.defaultDueTime, "09:00")
        XCTAssertEqual(merged.subtaskDisplay, "under_parent")
        XCTAssertEqual(merged.taskDisplayMode, "project")
    }

    func testAITD468_AnUnrelatedUpdateLeavesTheChoiceAlone() {
        var current = UserSettings()
        current.showListImages = false
        let merged = UserSettings.merging(UserSettings(subtaskDisplay: "under_parent"), into: current)
        XCTAssertEqual(merged.showListImages, false)
    }

    // MARK: - What a hidden image draws instead

    func testAITD468_HiddenImagesDrawAHashWhereThereIsRoomForOne() {
        XCTAssertEqual(ListImagesVisibility.Placeholder.forSize(16), .hash)
        XCTAssertEqual(ListImagesVisibility.Placeholder.forSize(12), .hash)
        // Below that a glyph is a smudge; the colour dot says the same thing legibly.
        XCTAssertEqual(ListImagesVisibility.Placeholder.forSize(8), .dot)
    }
}
