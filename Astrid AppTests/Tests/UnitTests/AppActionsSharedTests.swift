//  AppActionsSharedTests.swift
//  Guards for AITD-400 — the "a failed write must not vanish" mechanism is no longer Mac-only.
//
//  `MacErrorCenter` / `MacActions` / `MacFailureCopy` / `MacErrorBanner` lived under `Astrid Mac/`
//  behind `#if os(macOS)`. That meant iOS could only adopt the same guarantee by writing a second
//  copy — the drift this whole task family exists to stop.
//
//  This suite runs in the iOS target, so the fact that it COMPILES is half the guard: it names
//  types that used to be unavailable here at all.

import XCTest
@testable import Astrid_App

final class AppActionsSharedTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Half the point: iOS can see these at all. Before AITD-400 this file would not build.
    func testAITD400_TheFailureCopyRuleIsAvailableToIOS() {
        XCTAssertEqual(FailureCopy.message(for: "Delete list"),
                       NSLocalizedString("mac.failed.delete", comment: ""))
        XCTAssertEqual(FailureCopy.message(for: "Save notes"),
                       NSLocalizedString("mac.failed.save", comment: ""))
        XCTAssertEqual(FailureCopy.message(for: "Complete task"),
                       NSLocalizedString("mac.failed.complete", comment: ""))
        XCTAssertEqual(FailureCopy.message(for: "Invite user"),
                       NSLocalizedString("mac.failed.create", comment: ""))
    }

    /// An unrecognised verb must still say something — the whole mechanism exists so that a
    /// failure is never silent, and an empty banner would be the same bug wearing a hat.
    func testAITD400_AnUnknownVerbStillProducesCopy() {
        for context in ["Frobnicate widget", ""] {
            XCTAssertEqual(FailureCopy.message(for: context),
                           NSLocalizedString("mac.failed.generic", comment: ""))
            XCTAssertFalse(FailureCopy.message(for: context).isEmpty)
        }
    }

    @MainActor
    func testAITD400_ReportingAFailurePutsTheServersWordsInTheBanner() {
        struct Boom: LocalizedError { var errorDescription: String? { "network down" } }
        let center = AppErrorCenter.shared
        center.clear()
        center.report("Invite user", Boom())
        XCTAssertEqual(center.current?.text,
                       "\(FailureCopy.message(for: "Invite user")): network down",
                       "AITD-400: the localized category AND what the server actually said")
        center.clear()
        XCTAssertNil(center.current)
    }

    /// The mechanism must live where BOTH targets compile it, and must not be re-declared under
    /// `Astrid Mac/` — a second copy there is exactly the regression this removed.
    func testAITD400_TheMechanismIsSharedAndNotRedeclaredOnTheMac() throws {
        let shared = try source("Astrid App/Core/Platform/AppActions.swift")
        for type in ["final class AppErrorCenter", "enum FailureCopy", "enum AppActions"] {
            XCTAssertTrue(shared.contains(type), "\(type) belongs in the shared AppActions.swift")
        }
        XCTAssertTrue(try source("Astrid App/Core/Platform/AppErrorBanner.swift")
                        .contains("struct AppErrorBanner"))

        // Membership is by synchronized group: the Mac compiles everything under "Astrid App"
        // that is NOT an exception. Listing either file would take the mechanism away again.
        let project = try source("Astrid App.xcodeproj/project.pbxproj")
        for path in ["Core/Platform/AppActions.swift", "Core/Platform/AppErrorBanner.swift"] {
            XCTAssertFalse(project.contains("\(path),"),
                           "\(path) must stay OFF the Mac exception list")
        }

        let macFiles = FileManager.default.enumerator(
            at: RepositoryLocator.root.appendingPathComponent("Astrid Mac"),
            includingPropertiesForKeys: nil
        )
        for case let url as URL in macFiles! where url.pathExtension == "swift" {
            let src = try String(contentsOf: url, encoding: .utf8)
            for decl in ["class MacErrorCenter", "enum MacActions", "enum MacFailureCopy",
                         "struct MacErrorBanner"] {
                XCTAssertFalse(src.contains(decl),
                               "\(url.lastPathComponent) re-declares \(decl); it is shared now")
            }
        }
    }
}
