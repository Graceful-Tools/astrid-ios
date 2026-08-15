//  APIEndpointInventoryTests.swift
//  Keeps `docs/API_ENDPOINTS.md` honest (task b1a05e99).
//
//  Jon chose `AstridAPIClient` as the one HTTP client. That choice has a real cost, and it is
//  worth naming rather than glossing: the `APIEndpoint` enum it beat was the more READABLE shape
//  — one list of every endpoint, its method and its body type, checkable against the API contract
//  at a glance. `AstridAPIClient` spends its paths as inline string literals across 1,500+ lines,
//  so "which endpoints exist" becomes something you learn by reading.
//
//  `docs/API_ENDPOINTS.md` buys that readability back. But a hand-maintained list of anything is
//  wrong within a month, and a doc that is quietly wrong is worse than no doc — you trust it.
//  These tests are the only reason the file is worth anything: the moment a path is added,
//  renamed or removed in the source without the doc following, the suite fails and prints what
//  the file should say.

import XCTest
@testable import Astrid_App

final class APIEndpointInventoryTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }

    /// Every `/api/v1` literal in a source file, with interpolations flattened to `{id}` so the
    /// list is stable across renamed local variables.
    private func paths(inSourceAt relativePath: String) throws -> Set<String> {
        let url = repoRoot().appendingPathComponent(relativePath)
        let source = try String(contentsOf: url, encoding: .utf8)
        var found: Set<String> = []
        let pattern = try NSRegularExpression(pattern: "\"(/api/v1/[^\"]*)\"")
        let range = NSRange(source.startIndex..., in: source)
        for match in pattern.matches(in: source, range: range) {
            guard let r = Range(match.range(at: 1), in: source) else { continue }
            let interpolation = try NSRegularExpression(pattern: "\\\\\\([^)]*\\)")
            let raw = String(source[r])
            let flattened = interpolation.stringByReplacingMatches(
                in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "{id}")
            found.insert(flattened)
        }
        return found
    }

    private func documentedPaths() throws -> Set<String> {
        let url = repoRoot().appendingPathComponent("docs/API_ENDPOINTS.md")
        let doc = try String(contentsOf: url, encoding: .utf8)
        var found: Set<String> = []
        for line in doc.components(separatedBy: .newlines) where line.hasPrefix("- `/api/v1/") {
            let trimmed = line.dropFirst(3).dropLast()   // strip "- `" and trailing "`"
            found.insert(String(trimmed))
        }
        return found
    }

    // MARK: - The doc matches the code

    func testEveryEndpointInTheCodeIsDocumented() throws {
        let inCode = try paths(inSourceAt: "Astrid App/Core/Networking/AstridAPIClient.swift")
            .union(paths(inSourceAt: "Astrid App/Core/Networking/APIEndpoint.swift"))
        let documented = try documentedPaths()

        let undocumented = inCode.subtracting(documented)
        XCTAssertTrue(undocumented.isEmpty,
                      "Endpoints called but not in docs/API_ENDPOINTS.md:\n"
                      + undocumented.sorted().map { "- `\($0)`" }.joined(separator: "\n"))
    }

    /// The other direction. A path that lingers after the call site is deleted is how a list
    /// stops describing the app while still looking authoritative.
    func testNothingIsDocumentedThatTheCodeNoLongerCalls() throws {
        let inCode = try paths(inSourceAt: "Astrid App/Core/Networking/AstridAPIClient.swift")
            .union(paths(inSourceAt: "Astrid App/Core/Networking/APIEndpoint.swift"))
        let documented = try documentedPaths()

        let stale = documented.subtracting(inCode)
        XCTAssertTrue(stale.isEmpty,
                      "Documented but no longer called — delete these from docs/API_ENDPOINTS.md:\n"
                      + stale.sorted().map { "- `\($0)`" }.joined(separator: "\n"))
    }

    // MARK: - The decision itself

    /// The legacy client is closed to additions. This is the rule that decays first, because
    /// adding one more case beside 27 others always looks harmless.
    func testTheLegacyClientIsNotGrowing() throws {
        let legacy = try paths(inSourceAt: "Astrid App/Core/Networking/APIEndpoint.swift")
        XCTAssertLessThanOrEqual(
            legacy.count, 27,
            "APIEndpoint gained a path. It is closed (ASTRID.md §2a) — add it to AstridAPIClient.")
    }

    /// The decision has to be findable by someone who never read the task.
    func testTheDecisionIsRecordedWhereAgentsRead() throws {
        let astrid = try String(contentsOf: repoRoot().appendingPathComponent("ASTRID.md"),
                                encoding: .utf8)
        XCTAssertTrue(astrid.contains("`AstridAPIClient` is the HTTP client"),
                      "ASTRID.md must state which client is the one")
        XCTAssertTrue(astrid.contains("b1a05e99"),
                      "The decision should cite the task that settled it")
    }
}
