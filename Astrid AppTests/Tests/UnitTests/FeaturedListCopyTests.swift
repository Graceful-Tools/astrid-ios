//  FeaturedListCopyTests.swift
//  Task AITD-348 — the featured-list "Copy List" button copied nothing.
//
//  `TaskListView.copyList()` was:
//
//      private func copyList() async {
//          guard let _ = selectedList else { return }
//          isCopyingList = true
//          // TODO: Implement copy list API v1 endpoint
//          do { isCopyingList = false }
//      }
//
//  A user-reachable button that showed a spinner for one frame and did nothing. The TODO was
//  stale — `RemoteResourceService.copyList` already existed and the Mac was using it.
//
//  Two tests, aimed at the two ways this actually breaks:
//    * the plan type pins the re-entry rule, which is real logic worth checking directly;
//    * the source guard pins the thing that regressed — a button wired to a no-op. There was no
//      behaviour to mock, so only reading the call site can catch it coming back.

import XCTest
@testable import Astrid_App

final class FeaturedListCopyTests: XCTestCase {

    // MARK: - The re-entry rule

    func testACopyStartsWhenAListIsSelectedAndNothingIsInFlight() {
        XCTAssertEqual(FeaturedListCopyPlan.decide(selectedListId: "list-1", isCopying: false),
                       .copy(listId: "list-1"))
    }

    func testASecondTapWhileACopyIsInFlightIsIgnored() {
        // The spinner is the only affordance saying a copy is running, and it is small. Without
        // this the impatient double-tap files the list twice.
        XCTAssertEqual(FeaturedListCopyPlan.decide(selectedListId: "list-1", isCopying: true),
                       .ignore)
    }

    func testNothingHappensWithoutASelectedList() {
        XCTAssertEqual(FeaturedListCopyPlan.decide(selectedListId: nil, isCopying: false), .ignore)
    }

    // MARK: - The call site (AITD-348 itself)

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCopyListActuallyCallsTheCopyService() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Astrid App/Views/Tasks/TaskListView.swift"),
            encoding: .utf8
        )
        let body = try XCTUnwrap(Self.copyListBody(in: source), "copyList() is not in TaskListView any more")

        XCTAssertTrue(body.contains("RemoteResourceService.shared.copyList"),
                      "the Copy List button must actually copy the list — it was a no-op with a "
                      + "stale TODO while RemoteResourceService.copyList already existed and the "
                      + "Mac was using it (AITD-348). Body was:\n\(body)")
        XCTAssertFalse(body.contains("TODO"),
                       "the TODO in copyList() was stale — the v1 endpoint it was waiting for "
                       + "already shipped (AITD-348)")
    }

    func testCopyListRestoresItsSpinnerOnEveryPath() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Astrid App/Views/Tasks/TaskListView.swift"),
            encoding: .utf8
        )
        let body = try XCTUnwrap(Self.copyListBody(in: source))
        XCTAssertTrue(body.contains("defer { isCopyingList = false }"),
                      "a thrown error must not leave the spinner running forever")
    }

    /// The CODE of `private func copyList()`, up to the start of the next `private func`, with
    /// comment lines removed.
    ///
    /// Stripping comments is not tidiness — it is what makes these tests real. The stub's own TODO
    /// read "restore `defer { isCopyingList = false }`", so a naive substring check found that
    /// exact string inside the comment and passed against the broken code. A guard that a comment
    /// can satisfy guards nothing.
    private static func copyListBody(in source: String) -> String? {
        guard let start = source.range(of: "private func copyList()") else { return nil }
        let rest = source[start.upperBound...]
        let body: String
        if let end = rest.range(of: "\n    private func ") {
            body = String(rest[..<end.lowerBound])
        } else {
            body = String(rest)
        }
        return body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
