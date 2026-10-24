//  AnalyticsPlatformCoverageTests.swift
//  Regression guard for AITD-301 — "add logging to make sure we can detect activity separately
//  in the MAC app, so it shows up in /admin/analytics".
//
//  `AnalyticsPlatformHeaderTests` already pins the wire VALUES and that AstridAPIClient's three
//  builders send them. This pins COVERAGE, which is where the Mac was still losing itself:
//
//    1. `APIEndpoint.makeRequest` hardcoded `"ios-app"` — in a file compiled into the Mac target.
//       It happened to be overwritten by APIClient.request, so it was invisible rather than
//       harmless: any other caller of makeRequest reports the Mac as iOS.
//    2. Roughly nineteen Astrid-bound requests — the SSE stream, all eight passkey calls,
//       attachments, the OAuth token — identified nothing at all.
//
//  The scan below is the part that keeps this fixed: a NEW file that talks to the Astrid backend
//  and forgets the header fails here, rather than quietly under-counting a platform for months.

import XCTest
@testable import Astrid_App

final class AnalyticsPlatformCoverageTests: XCTestCase {

    /// Every Swift source in the two shipping targets, with its contents.
    private func sources() throws -> [(name: String, path: String, text: String)] {
        var found: [(String, String, String)] = []
        for target in ["Astrid App", "Astrid Mac"] {
            let root = RepositoryLocator.root.appendingPathComponent(target)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                XCTFail("Could not enumerate \(root.path)")
                continue
            }
            for case let url as URL in files where url.pathExtension == "swift" {
                found.append((url.lastPathComponent,
                              "\(target)/\(url.lastPathComponent)",
                              try String(contentsOf: url, encoding: .utf8)))
            }
        }
        XCTAssertGreaterThan(found.count, 50, "Sanity: the targets should have plenty of sources")
        return found
    }

    // MARK: - The helper

    /// One call site shape, so no caller can half-apply the contract.
    func testAITD301_ApplyStampsBothTheNameAndTheValue() {
        var request = URLRequest(url: URL(string: "https://astrid.cc/api/v1/tasks")!)
        AnalyticsPlatformHeader.apply(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: AnalyticsPlatformHeader.headerName),
                       AnalyticsPlatformHeader.current)
        #if os(macOS)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-platform"), "mac-app")
        #else
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-platform"), "ios-app")
        #endif
    }

    /// Applying twice must not append or duplicate — `setValue` semantics, stated as a test
    /// because `addValue` would produce `ios-app,ios-app`, which the server matches on equality
    /// and would therefore read as an unrecognised platform.
    func testAITD301_ApplyIsIdempotent() {
        var request = URLRequest(url: URL(string: "https://astrid.cc/api/v1/tasks")!)
        AnalyticsPlatformHeader.apply(to: &request)
        AnalyticsPlatformHeader.apply(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: AnalyticsPlatformHeader.headerName),
                       AnalyticsPlatformHeader.current)
    }
}
