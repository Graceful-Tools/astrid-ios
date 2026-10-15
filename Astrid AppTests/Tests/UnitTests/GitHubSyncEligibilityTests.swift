//  GitHubSyncEligibilityTests.swift
//  Regression guard for AITD-491 — "[iOS/Mac] GitHub Projects boards, part 2", the safety item:
//  the on-device GitHub Issues engine must not touch a list the SERVER already mirrors through
//  the `github_project` backend, or two engines write one issue (spec §11.3).

import XCTest
@testable import Astrid_App

final class GitHubSyncEligibilityTests: XCTestCase {

    private func list(_ id: String, backedByGitHub: Bool = false,
                      isVirtual: Bool = false, listType: String? = "regular") -> TaskList {
        var list = TestHelpers.createTestList(id: id, isVirtual: isVirtual)
        list.listType = listType
        list.supports = backedByGitHub
            ? ListSupports(multipleAssignees: true, repeatMode: .spawn)
            : nil
        return list
    }

    private func link(_ id: String, to listId: String) -> ExternalListLinkDTO {
        ExternalListLinkDTO(id: id, astridListId: listId, remoteContainerId: "acme/\(id)",
                            remoteContainerName: "acme/\(id)", cursor: nil)
    }

    // MARK: - The engine's link set

    func test_aitd491_aLinkToAGitHubBackedListIsNotSynced() {
        let lists = [list("board", backedByGitHub: true), list("home")]
        let links = [link("one", to: "board"), link("two", to: "home")]

        let syncable = GitHubSyncEligibility.syncableLinks(links, in: lists)

        XCTAssertEqual(syncable.map(\.id), ["two"],
                       "the server owns the issues on a GitHub-backed board; the device must not push them too")
    }

    /// Every classic account: the engine sees exactly the links it always did.
    func test_aitd491_everyClassicListStillSyncs() {
        let lists = [list("home"), list("work")]
        let links = [link("one", to: "home"), link("two", to: "work")]

        XCTAssertEqual(GitHubSyncEligibility.syncableLinks(links, in: lists).map(\.id), ["one", "two"])
    }

    /// At launch the list cache can be empty before the links arrive. An unknown list is synced,
    /// because refusing one would silently stop a classic account's sync; a GitHub-backed list is
    /// recognised as soon as the lists load.
    func test_aitd491_aLinkWhoseListIsNotLoadedYetIsStillSynced() {
        XCTAssertEqual(GitHubSyncEligibility.syncableLinks([link("one", to: "unknown")], in: []).map(\.id),
                       ["one"])
    }

    func test_aitd491_aBoardWithNoLinkChangesNothing() {
        let lists = [list("board", backedByGitHub: true)]
        XCTAssertEqual(GitHubSyncEligibility.syncableLinks([link("one", to: "home")], in: lists).map(\.id),
                       ["one"])
    }

    // MARK: - What the repo picker may offer

    func test_aitd491_thePickerDoesNotOfferAGitHubBackedList() {
        let lists = [
            list("board", backedByGitHub: true),
            list("home"),
            list("smart", isVirtual: true),
            list("doing", listType: "status"),
        ]

        XCTAssertEqual(GitHubSyncEligibility.linkableLists(lists).map(\.id), ["home"],
                       "a board the server mirrors cannot be linked to a repo in the first place")
    }

    // MARK: - The signal itself

    func test_aitd491_aSpawningBoardIsTheGitHubBackedList() {
        XCTAssertTrue(list("board", backedByGitHub: true).isGitHubBacked)
        XCTAssertFalse(list("home").isGitHubBacked)
        var older = list("older")
        older.supports = ListSupports(multipleAssignees: true)
        XCTAssertFalse(older.isGitHubBacked, "a server that sends only the first supports key is classic")
    }

    /// `list.backend` reached the v1 wire (astrid-web AWTD-1256): it decides, and `supports` is
    /// only the fallback for a server older than the field.
    func test_aitd491_backendDecidesGitHubBackedAndSurvivesTheCache() throws {
        let decoder = JSONDecoder()
        let board = try decoder.decode(TaskList.self, from: Data(
            #"{"id":"l1","name":"Board","backend":"github_project"}"#.utf8))
        XCTAssertTrue(board.isGitHubBacked, "backend alone decides it, whatever supports says")
        let again = try decoder.decode(TaskList.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(again.backend, "github_project", "survives the app's own cache")

        let older = try decoder.decode(TaskList.self, from: Data(
            #"{"id":"l2","name":"Board","supports":{"repeatMode":"spawn"}}"#.utf8))
        XCTAssertTrue(older.isGitHubBacked, "no backend key: the supports derivation still holds")

        for classic in [
            #"{"id":"l3","name":"Home","backend":null}"#,
            #"{"id":"l4","name":"Later","backend":"aBackendFromLater"}"#,
        ] {
            XCTAssertFalse(try decoder.decode(TaskList.self, from: Data(classic.utf8)).isGitHubBacked, classic)
        }
        XCTAssertEqual(GitHubSyncEligibility.linkableLists([board]).map(\.id), [],
                       "a board known only by its backend is not offered for linking")
    }
}
