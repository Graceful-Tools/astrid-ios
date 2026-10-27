//  ListImagesVisibilityTests.swift
//  List images are permanent (AITD-560). The hide_list_images experiment (AITD-468) is gone from
//  web: GET /api/v1/features no longer returns the key, and `showListImages` on
//  /api/v1/users/me/smart-tasks is deprecated — served only until no client reads or writes it,
//  after which web drops the column. These pin that this client is one of the ones that doesn't.

import XCTest
@testable import Astrid_App

final class ListImagesVisibilityTests: XCTestCase {

    func testAITD560_HideListImagesIsNotAFeature() {
        XCTAssertFalse(AstridFeature.allCases.map(\.rawValue).contains("hide_list_images"))
    }

    func testAITD560_SettingsNeverSendShowListImages() throws {
        // A server still serving the deprecated field must not get it echoed back on the next PATCH.
        let decoded = try JSONDecoder().decode(
            UserSettings.self, from: Data(#"{"subtaskDisplay":"indented","showListImages":false}"#.utf8))
        for settings in [decoded, UserSettings()] {
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
            XCTAssertNotNil(json)
            XCTAssertNil(json?["showListImages"])
        }
    }
}
