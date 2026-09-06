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

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }

    /// Every Swift source in the two shipping targets, with its contents.
    private func sources() throws -> [(name: String, path: String, text: String)] {
        var found: [(String, String, String)] = []
        for target in ["Astrid App", "Astrid Mac"] {
            let root = repoRoot().appendingPathComponent(target)
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

    // MARK: - The value is never restated

    /// A hardcoded platform string is the bug this task exists to remove: `APIEndpoint` said
    /// `"ios-app"` inside a file the Mac also compiles. The contract has ONE definition.
    func testAITD301_NoSourceHardcodesAPlatformValueOrHeaderName() throws {
        var violations: [String] = []
        for source in try sources() where source.name != "AnalyticsPlatformHeader.swift" {
            for (index, line) in source.text.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else { continue }
                for literal in ["\"ios-app\"", "\"mac-app\"", "\"x-platform\""] where code.contains(literal) {
                    violations.append("\(source.path):\(index + 1) — \(literal)")
                }
            }
        }
        XCTAssertEqual(violations, [], """
            Platform identity is a cross-repo contract with astrid-web's lib/analytics-events.ts \
            and must come from AnalyticsPlatformHeader, never a literal:
            \(violations.joined(separator: "\n"))
            """)
    }

    // MARK: - Every Astrid-bound request identifies the app

    /// Files that build a `URLRequest` against the Astrid backend must stamp the platform.
    ///
    /// Third parties are deliberately excluded rather than exempted by name where possible: we
    /// send our analytics header to our own server only. Google's token endpoint and the blob
    /// storage host get nothing.
    func testAITD301_EveryFileBuildingAnAstridRequestSendsThePlatform() throws {
        /// Talks only to a third party, so it must NOT carry our header.
        let thirdPartyOnly: Set<String> = ["GoogleSignInManager.swift"]

        var missing: [String] = []
        for source in try sources() {
            guard source.text.contains("URLRequest(url:") else { continue }
            guard !thirdPartyOnly.contains(source.name) else {
                XCTAssertFalse(source.text.contains("AnalyticsPlatformHeader"),
                               "\(source.path) talks to a third party and must not send our platform header")
                continue
            }
            // Astrid-bound iff it builds a URL from our own base.
            let astridBound = source.text.contains("Constants.API.baseURL")
                || source.text.contains("baseURL.appendingPathComponent")
                || source.text.contains("baseURL:")
            guard astridBound else { continue }
            if !source.text.contains("AnalyticsPlatformHeader") {
                missing.append(source.path)
            }
        }
        XCTAssertEqual(missing.sorted(), [], """
            These build requests to the Astrid backend without identifying the platform, so their \
            traffic cannot be attributed to iOS or Mac:
            \(missing.sorted().joined(separator: "\n"))
            """)
    }

    /// The four surfaces this task found unidentified, named so the fix cannot be partially
    /// reverted without a failure that says which one went.
    func testAITD301_TheSurfacesThisTaskFixedStayFixed() throws {
        let required = ["SSEClient.swift",           // the app is OPEN — the clearest Mac signal
                        "PasskeyManager.swift",      // sign-in: a new Mac user's first traffic
                        "AttachmentService.swift",
                        "OAuthManager.swift",
                        "APIEndpoint.swift"]
        let byName = Dictionary(uniqueKeysWithValues: try sources().map { ($0.name, $0) })
        for name in required {
            guard let source = byName[name] else {
                XCTFail("\(name) not found — if it was renamed, keep it covered")
                continue
            }
            XCTAssertTrue(source.text.contains("AnalyticsPlatformHeader"),
                          "\(name) must identify the platform on its requests")
        }
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
