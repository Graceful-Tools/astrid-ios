//  PresentationAnchorSelectionTests.swift
//  Task AITD-347 — presentationAnchor() trapped when the first connected scene had no window.
//
//  The old iOS branch was:
//
//      guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//            let window = scene.windows.first else { fatalError("No window available") }
//
//  `connectedScenes` is a Set and the app declares `UIApplicationSupportsMultipleScenes`, so on
//  iPad "first" is arbitrary. Four sign-in paths call this (`PasskeyManager`, `AppleSignInManager`,
//  `GoogleSignInManager`, `OAuthWebConnector`), so starting a sign-in from a second window could
//  terminate the app.
//
//  Windows are Strings here on purpose: the ordering is the whole behaviour, and it does not
//  depend on anything a real UIWindow does.

import XCTest
import UIKit
@testable import Astrid_App

final class PresentationAnchorSelectionTests: XCTestCase {

    private typealias Scene = PresentationAnchorSelection.SceneCandidate<String>

    func testTheForegroundScenesKeyWindowWins() {
        // The bug, stated directly: a windowless background scene enumerating first must not
        // decide the answer, and must certainly not be fatal.
        let chosen = PresentationAnchorSelection.choose(from: [
            Scene(activationState: .background, windows: []),
            Scene(activationState: .foregroundActive, windows: ["a", "b"], keyWindow: "b"),
        ])
        XCTAssertEqual(chosen, "b")
    }

    func testAForegroundSceneBeatsABackgroundOneEvenWhenTheBackgroundOneHasWindows() {
        let chosen = PresentationAnchorSelection.choose(from: [
            Scene(activationState: .background, windows: ["bg"], keyWindow: "bg"),
            Scene(activationState: .foregroundActive, windows: ["fg"]),
        ])
        XCTAssertEqual(chosen, "fg", "the sheet belongs on the window the user is looking at")
    }

    func testAForegroundSceneWithNoKeyWindowStillContributesItsFirstWindow() {
        let chosen = PresentationAnchorSelection.choose(from: [
            Scene(activationState: .foregroundActive, windows: ["only"], keyWindow: nil),
        ])
        XCTAssertEqual(chosen, "only")
    }

    func testForegroundInactiveIsPreferredOverBackground() {
        // Mid-transition — still on screen, still a better anchor than a suspended scene.
        let chosen = PresentationAnchorSelection.choose(from: [
            Scene(activationState: .background, windows: ["bg"], keyWindow: "bg"),
            Scene(activationState: .foregroundInactive, windows: ["inactive"]),
        ])
        XCTAssertEqual(chosen, "inactive")
    }

    func testAnActiveSceneWithNoWindowsFallsThroughToOneThatHasThem() {
        let chosen = PresentationAnchorSelection.choose(from: [
            Scene(activationState: .foregroundActive, windows: []),
            Scene(activationState: .background, windows: ["bg"]),
        ])
        XCTAssertEqual(chosen, "bg",
                       "a window somewhere beats no window — the old code called this fatal")
    }

    func testNoScenesAtAllReturnsNilRatherThanTrapping() {
        XCTAssertNil(PresentationAnchorSelection.choose(from: [] as [Scene]))
    }

    func testScenesWithoutWindowsReturnNilRatherThanTrapping() {
        XCTAssertNil(PresentationAnchorSelection.choose(from: [
            Scene(activationState: .background, windows: []),
            Scene(activationState: .unattached, windows: []),
        ]))
    }

    // MARK: - The call site

    func testPlatformNoLongerTrapsWhenThereIsNoWindow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Platform/Platform.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains(#"fatalError("No window available")"#),
                       "a missing window must not terminate the app — the macOS branch has always "
                       + "fallen back instead, and a sheet on the wrong window is recoverable "
                       + "where a crash is not (AITD-347)")
        XCTAssertTrue(source.contains("PresentationAnchorSelection.choose"),
                      "the iOS branch must use the shared, tested selection rather than "
                      + "connectedScenes.first")
    }
}
