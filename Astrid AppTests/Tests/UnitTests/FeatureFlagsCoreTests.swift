//  FeatureFlagsCoreTests.swift
//  The whole feature-flag map comes from astrid-core's `featureFlags` (AITD-620, slice 13), not
//  from `GET /api/v1/features` on the app's own HTTP stack. The round trip (conditional request,
//  304, offline failure) is the core's own test (`dispatch/tests/account.rs`); what is pinned here
//  is the Swift half: how the command is spelled and how its answer reads.

import AstridCore
import XCTest
@testable import Astrid_App

final class FeatureFlagsCoreTests: XCTestCase {
    func testTheFlagMapIsTheCoresFeatureFlagsCommand_AITD620() throws {
        let data = Data(try CoreJSON.encode(FeatureFlagCommands.flags()).utf8)
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(sent["kind"] as? String, "featureFlags")
    }

    /// Every flag comes back, rollouts nobody named included, with the version a
    /// `featureFlagsUpdated` frame is compared against.
    func testTheAnswerKeepsEveryFlagAndTheVersion_AITD620() throws {
        let answer = try CoreJSON.answer(
            #"{"ok":true,"value":{"version":7,"features":{"project_mode":true,"google_tasks":false,"a_rollout":true}}}"#,
            as: EffectiveFeaturesResponse.self)
        XCTAssertEqual(answer.version, 7)
        XCTAssertEqual(answer.features, ["project_mode": true, "google_tasks": false, "a_rollout": true])
    }

    /// An older server sends no version; the core passes that through as null, which must read as
    /// version 0 rather than fail and leave the cached flags standing forever.
    func testAMissingVersionReadsAsZero_AITD620() throws {
        let answer = try CoreJSON.answer(
            #"{"ok":true,"value":{"version":null,"features":{"project_mode":true}}}"#,
            as: EffectiveFeaturesResponse.self)
        XCTAssertEqual(answer.version, 0)
        XCTAssertEqual(answer.features["project_mode"], true)
    }
}
