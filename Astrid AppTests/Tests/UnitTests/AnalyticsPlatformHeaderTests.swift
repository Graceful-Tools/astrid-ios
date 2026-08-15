//  AnalyticsPlatformHeaderTests.swift
//  Regression for task 119cabc3 — "[mac] make sure that mac app is registered in Astrid Analytics."
//
//  The apps sent NOTHING that identified them: no `x-platform` header and no custom user agent,
//  on any of AstridAPIClient's three request builders. The server's `detectPlatform()` therefore
//  fell back to sniffing the user agent URLSession composes for us, which matches on `AstridApp/`
//  or `Astrid/` — and the bundle name produces `Astrid App/231 CFNetwork/…`, containing neither.
//
//  So this is not only "Mac is missing from the dashboard". Mac had no bucket to land in at all
//  (the server's platform list has no MAC_APP), and iOS was very likely being counted as UNKNOWN.
//
//  The fix is to STATE the platform rather than let it be inferred. These pin the value, because
//  it is a cross-repo contract: `lib/analytics-events.ts` matches `x-platform` exactly, so a typo
//  here is silently indistinguishable from sending nothing.

import XCTest
@testable import Astrid_App

final class AnalyticsPlatformHeaderTests: XCTestCase {

    /// The wire values the server matches. Changing either is a contract change with astrid-web.
    func testTheWireValuesMatchWhatTheServerLooksFor() {
        XCTAssertEqual(AnalyticsPlatformHeader.iOS, "ios-app")
        XCTAssertEqual(AnalyticsPlatformHeader.mac, "mac-app")
        XCTAssertEqual(AnalyticsPlatformHeader.headerName, "x-platform")
    }

    /// This build says exactly one thing about itself, and on iOS it is the iOS value.
    /// (The Mac target compiles the same file and gets `mac-app` from the same switch.)
    func testThisBuildIdentifiesItself() {
        #if os(macOS)
        XCTAssertEqual(AnalyticsPlatformHeader.current, AnalyticsPlatformHeader.mac)
        #else
        XCTAssertEqual(AnalyticsPlatformHeader.current, AnalyticsPlatformHeader.iOS)
        #endif
    }

    /// Never empty and never whitespace: an empty header is worse than no header, because the
    /// server would read it as a present-but-unrecognised platform rather than falling back.
    func testTheValueIsAlwaysSubstantive() {
        XCTAssertFalse(AnalyticsPlatformHeader.current.isEmpty)
        XCTAssertEqual(AnalyticsPlatformHeader.current,
                       AnalyticsPlatformHeader.current.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Every request carries it

    /// A header set in two of three request builders is the same bug in a smaller disguise —
    /// the dashboard would under-count by whichever calls happened to use the third.
    func testEveryRequestBuilderSendsTheHeader() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // UnitTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // Astrid AppTests
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent("Astrid App/Core/Networking/AstridAPIClient.swift"),
            encoding: .utf8)

        let acceptHeaders = source.components(separatedBy: "forHTTPHeaderField: \"Accept\"").count - 1
        // Counted by the CONSTANT, not by the literal "x-platform": call sites must go through
        // the shared value, or the cross-repo contract has a second definition to drift from.
        let platformHeaders = source
            .components(separatedBy: "AnalyticsPlatformHeader.headerName").count - 1

        XCTAssertGreaterThan(acceptHeaders, 0, "Sanity: the Accept header should exist")
        XCTAssertGreaterThanOrEqual(
            platformHeaders, acceptHeaders,
            "Every request builder that sets Accept must also identify the platform")
        XCTAssertFalse(source.contains("\"x-platform\""),
                       "Use AnalyticsPlatformHeader.headerName rather than the raw string")
    }
}
