//  StaleV1TodoTests.swift
//  AITD-349 — "not yet in API v1" comments that outlived the gap they described.
//
//  Two of the three TODO markers in the whole tree said a v1 endpoint was missing when it was
//  not, and each one had cost attached:
//
//    * `ListService.getListMembers` answered "[]" — "this list has no members" — for any caller
//      that trusted the comment and used it. Nothing did, which is the only reason it was
//      hygiene and not a bug: the real read has always been `ListMemberService` →
//      `GET /api/v1/lists/{id}/members`.
//    * `ListService.toggleFavorite` warned that favoriting was waiting on v1 while doing the
//      correct v1 thing, and `APIEndpoint.favoriteList` sat beside it as an unreachable case —
//      a path, a method override and a body encoder for a request nothing sends.
//
//  A comment that describes an absence is a claim about the API, and a wrong one sends the next
//  reader to build something that already exists (AITD-348 was the same shape, but there the
//  stub was user-reachable and the button really did nothing). These assertions are source-text
//  checks because that is where the defect lives: the code compiled and passed either way.

import XCTest
@testable import Astrid_App

final class StaleV1TodoTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func swiftSources() throws -> [(path: String, text: String)] {
        let fm = FileManager.default
        var results: [(String, String)] = []
        for target in ["Astrid App", "Astrid Mac"] {
            let root = repoRoot().appendingPathComponent(target)
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                results.append((url.lastPathComponent, text))
            }
        }
        return results
    }

    /// The claim itself. Any file asserting v1 lacks something is either wrong or describes work
    /// that should be a task rather than a comment nobody is accountable for.
    func testNoSourceFileClaimsAnEndpointIsMissingFromAPIV1() throws {
        let offenders = try swiftSources()
            .filter { $0.text.range(of: #"(?i)(not yet|TODO).{0,60}API v1"#, options: .regularExpression) != nil }
            .map(\.path)

        XCTAssertTrue(offenders.isEmpty,
                      "These files still claim API v1 is missing an endpoint (AITD-349): "
                      + offenders.sorted().joined(separator: ", "))
    }

    /// The stub that silently reported every shared list as empty.
    func testListServiceHasNoMemberReadingStub() throws {
        let listService = try source("Astrid App/Core/Services/ListService.swift")
        XCTAssertFalse(listService.contains("func getListMembers"),
                       "ListService.getListMembers returned [] and had no callers — member reads "
                       + "go through ListMemberService. Delete it rather than let it be found.")
    }

    /// The unreachable legacy case. `AstridAPIClient` is the one client (b1a05e99); a favorite
    /// is a `PUT /api/v1/lists/{id}` with `isFavorite`, so nothing constructs this endpoint.
    func testTheLegacyClientCarriesNoUnreachableFavoritePath() throws {
        let endpoints = try source("Astrid App/Core/Networking/APIEndpoint.swift")
        XCTAssertFalse(endpoints.contains("favoriteList"),
                       "APIEndpoint.favoriteList is constructed nowhere — it is a path, a method "
                       + "override and a body encoder for a request that is never sent.")
    }

    /// Favoriting rides `updateList` on purpose. Saying so where the call is made is what keeps
    /// this from being re-filed as a missing endpoint a third time.
    func testTheFavoriteCallSiteExplainsWhyItUsesUpdateList() throws {
        let listService = try source("Astrid App/Core/Services/ListService.swift")
        XCTAssertTrue(listService.contains("isFavorite is a field on the list"),
                      "toggleFavorite should say why it goes through updateList, or the missing "
                      + "/favorite endpoint gets re-filed.")
    }
}
