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

    /// A second failure replaces the first and restarts the clock, so the newer banner gets its
    /// full time on screen rather than vanishing on the first one's timer (AITD-538).
    @MainActor
    func testAITD538_ASecondReportReplacesTheFirstAndRestartsTheDismissal() async throws {
        struct Boom: LocalizedError { let text: String; var errorDescription: String? { text } }
        let center = AppErrorCenter(dismissAfter: .milliseconds(400))
        defer { center.clear() }

        center.report("Save due date", Boom(text: "first"))
        try await _Concurrency.Task.sleep(for: .milliseconds(250))
        center.report("Delete subtask", Boom(text: "second"))
        XCTAssertEqual(center.current?.text, "\(FailureCopy.message(for: "Delete subtask")): second")

        // Past the first report's deadline, inside the second's.
        try await _Concurrency.Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(center.current?.text, "\(FailureCopy.message(for: "Delete subtask")): second",
                       "the first report's timer must not dismiss the second banner")

        try await _Concurrency.Task.sleep(for: .milliseconds(500))
        XCTAssertNil(center.current, "the banner dismisses itself")
    }

    @MainActor
    func testAITD538_EachReportIsItsOwnBannerEvenWithTheSameText() {
        let center = AppErrorCenter(dismissAfter: .seconds(60))
        defer { center.clear() }

        center.show("Couldn't save")
        let first = center.current
        center.show("Couldn't save")

        XCTAssertNotEqual(first?.id, center.current?.id, "a repeat failure must redraw, not look like nothing happened")
    }
}
