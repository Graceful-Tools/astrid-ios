//  SearchTotalContractTests.swift
//  Contract guard for AITD-321 — "Confirm nothing reads `total` from GET /api/v1/search".
//
//  Web task f9ba26b3 made the exact result count on /api/v1/search opt-in. The endpoint was
//  running its unindexed ILIKE predicate twice per page — once for the rows, once for a count
//  used only to decide whether a next page existed — so `total` is now EXACT on the last page,
//  `null` on every earlier page, and exact everywhere only if the caller passes
//  `includeTotal=true`. Pagination is unchanged: `nextCursor` is derived by fetching one row
//  past the page.
//
//  The audit for AITD-321 found iOS calls that endpoint nowhere. `SearchService` searches the
//  in-memory `TaskService.shared.tasks` when online and CoreData when offline — its own comment
//  says "API doesn't have search endpoint" — and the only server paths with "search" in them are
//  /api/v1/users/search and /api/v1/contacts/search, which are different endpoints with different
//  response shapes (`UserSearchResponse`, `ContactSearchResponse`) and neither carries a `total`.
//
//  So AITD-321 closes as verified, and this file is what keeps it verified. A future caller of
//  /api/v1/search that reads `total` without opting in would read `null` on every page but the
//  last — a result count that renders as 0, or a paging calculation that stops early — and the
//  audit that would catch it is this test rather than someone remembering a web change from
//  September 2026.

import XCTest

final class SearchTotalContractTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }

    /// Every Swift source that ships in a product: both apps, the share extension, and the code
    /// they share. The extension makes no API calls today, but a guard that only covers the places
    /// a caller happens to live now is the guard that misses the next one.
    private func appSources() throws -> [(path: String, source: String)] {
        var sources: [(String, String)] = []
        for target in ["Astrid App", "Astrid Mac", "Astrid", "Shared"] {
            let root = repositoryRoot.appendingPathComponent(target)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                XCTFail("Could not enumerate \(root.path)")
                continue
            }
            for case let fileURL as URL in files where fileURL.pathExtension == "swift" {
                sources.append(("\(target)/\(fileURL.lastPathComponent)",
                                try String(contentsOf: fileURL, encoding: .utf8)))
            }
        }
        XCTAssertFalse(sources.isEmpty, "The app source tree moved; this guard is scanning nothing.")
        return sources
    }

    /// The state AITD-321 verified: nobody calls the endpoint at all.
    ///
    /// If this ever fails, the failure is not the bug — calling /api/v1/search is fine and may be
    /// an improvement over filtering the cached task list. The failure is a prompt to satisfy the
    /// contract in `testAnyCallerOfTheSearchEndpointHandlesAnAbsentTotal` below, and then to
    /// update this test to name the new caller instead of asserting there is none.
    func testNoAppCodeCallsTheV1SearchEndpoint() throws {
        let callers = try appSources()
            .filter { $0.source.contains("/api/v1/search") }
            .map(\.path)

        XCTAssertEqual(callers, [], """
            iOS gained a caller of /api/v1/search. Its `total` is null on every page but the last
            unless the request passes includeTotal=true — see AITD-321:
            \(callers.joined(separator: "\n"))
            """)
    }

    /// The rule that outlives the audit. A caller either opts in to the exact count or treats it
    /// as optional; what it must not do is decode `total` as a non-optional Int and trust it.
    func testAnyCallerOfTheSearchEndpointHandlesAnAbsentTotal() throws {
        var violations: [String] = []

        for (path, source) in try appSources() where source.contains("/api/v1/search") {
            let optsIn = source.contains("includeTotal")
            // A non-optional `let total: Int` in the same file is the shape that breaks: it fails
            // to decode outright once the server sends null.
            let decodesTotalAsRequired = source.range(
                of: "let\\s+total\\s*:\\s*Int(?!\\?)",
                options: .regularExpression
            ) != nil

            if decodesTotalAsRequired && !optsIn {
                violations.append("\(path): decodes a required `total` without passing includeTotal=true")
            }
        }

        XCTAssertEqual(violations, [], """
            /api/v1/search returns `total: null` on every page but the last. A caller must either
            request includeTotal=true or decode `total` as optional — AITD-321:
            \(violations.joined(separator: "\n"))
            """)
    }

    /// The endpoints iOS *does* call are neighbours with similar names and no `total` field.
    /// Pinning them keeps a future reader from assuming the AITD-321 change touched these.
    func testTheUserAndContactSearchEndpointsAreUnrelated() throws {
        let sources = try appSources()
        XCTAssertTrue(sources.contains { $0.source.contains("/api/v1/users/search") },
                      "The user-search endpoint moved; re-check which search endpoints iOS calls.")
        XCTAssertTrue(sources.contains { $0.source.contains("/api/v1/contacts/search") },
                      "The contact-search endpoint moved; re-check which search endpoints iOS calls.")
    }
}
