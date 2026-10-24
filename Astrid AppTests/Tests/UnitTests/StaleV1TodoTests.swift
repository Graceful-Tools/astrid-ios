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

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The stub that silently reported every shared list as empty.
    func testListServiceHasNoMemberReadingStub() throws {
        let listService = try source("Astrid App/Core/Services/ListService.swift")
        XCTAssertFalse(listService.contains("func getListMembers"),
                       "ListService.getListMembers returned [] and had no callers — member reads "
                       + "go through ListMemberService. Delete it rather than let it be found.")
    }
}
