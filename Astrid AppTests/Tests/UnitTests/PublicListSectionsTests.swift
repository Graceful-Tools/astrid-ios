//  PublicListSectionsTests.swift
//  Regression guard for Task dfb037c7 — "[mac] move public lists below user lists and allow the
//  user to view the tasks on the public lists. See iOS and web."
//
//  Mac had no public lists in the sidebar at all — they lived only behind a sheet — so there was
//  nothing to move below anything. The sections have to be ADDED, matching iOS.
//
//  The split is not cosmetic, which is why it belongs in one tested place rather than being
//  written a third time (iOS has it inline today):
//
//    - "Public & Shared" — collaborative lists, the ones you can contribute to
//    - "Public Lists"    — copy-only, which you may read and copy but not write
//
//  Getting that backwards would offer someone a write affordance on a list they cannot write to,
//  or hide a collaborative list among the read-only ones.

import XCTest
@testable import Astrid_App

final class PublicListSectionsTests: XCTestCase {

    private func list(_ id: String, type: String?) -> TaskList {
        var l = TaskList(id: id, name: "L\(id)", privacy: .PUBLIC)
        l.publicListType = type
        return l
    }

    // MARK: - Which bucket

    func testCollaborativeListsAreTheSharedSection() {
        let lists = [list("1", type: "collaborative"), list("2", type: "copy_only")]
        XCTAssertEqual(PublicListSections.collaborative(lists).map(\.id), ["1"])
    }

    func testCopyOnlyListsAreTheBrowseSection() {
        let lists = [list("1", type: "collaborative"), list("2", type: "copy_only")]
        XCTAssertEqual(PublicListSections.browsable(lists).map(\.id), ["2"])
    }

    /// A list with NO type is browse-only. Defaulting the other way would offer a write affordance
    /// on a list nobody said was collaborative — the unsafe direction of the two.
    func testAnUntypedListIsBrowseOnly() {
        let lists = [list("1", type: nil)]
        XCTAssertTrue(PublicListSections.collaborative(lists).isEmpty)
        XCTAssertEqual(PublicListSections.browsable(lists).map(\.id), ["1"])
    }

    /// An unrecognised type from a newer server is also browse-only, for the same reason.
    func testAnUnknownTypeIsBrowseOnly() {
        let lists = [list("1", type: "some_future_type")]
        XCTAssertTrue(PublicListSections.collaborative(lists).isEmpty)
        XCTAssertEqual(PublicListSections.browsable(lists).map(\.id), ["1"])
    }

    /// Every list lands in exactly one bucket — none dropped, none duplicated.
    func testEveryListIsInExactlyOneSection() {
        let lists = [list("1", type: "collaborative"), list("2", type: "copy_only"),
                     list("3", type: nil), list("4", type: "collaborative")]
        let ids = (PublicListSections.collaborative(lists) + PublicListSections.browsable(lists))
            .map(\.id).sorted()
        XCTAssertEqual(ids, ["1", "2", "3", "4"])
    }

    // MARK: - The sidebar cap

    /// Two rows per section, with the rest behind "see all". Without a cap someone else's lists
    /// swamp the sidebar that is meant to be about YOUR lists.
    func testEachSectionShowsAtMostTwoRows() {
        let many = (1...5).map { list("\($0)", type: "collaborative") }
        XCTAssertEqual(PublicListSections.sidebarRows(many).map(\.id), ["1", "2"])
        XCTAssertTrue(PublicListSections.hasMore(many))
    }

    func testASmallSectionShowsEverythingAndOffersNoMore() {
        let few = [list("1", type: "collaborative"), list("2", type: "collaborative")]
        XCTAssertEqual(PublicListSections.sidebarRows(few).count, 2)
        XCTAssertFalse(PublicListSections.hasMore(few), "exactly two is not 'more'")
    }

    func testAnEmptySectionIsNotShownAtAll() {
        XCTAssertTrue(PublicListSections.sidebarRows([]).isEmpty)
        XCTAssertFalse(PublicListSections.hasMore([]))
    }

    // MARK: - Both platforms ask the same rule

    func testTheSidebarsUseTheSharedRule() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for relative in ["Astrid Mac/App/MacRootView.swift",
                         "Astrid App/Views/Lists/ListSidebarView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertTrue(source.contains("PublicListSections."),
                          "\(relative) must ask the shared rule rather than re-deriving the split")
        }
    }

    func testDomainListPredicateTreatsStatusRowsAsNonLists() {
        var status = TaskList(id: "status", name: "Ready")
        status.listType = "status"
        XCTAssertFalse(status.isDomainList)
        XCTAssertTrue(status.isStatusList)

        var regular = TaskList(id: "regular", name: "Inbox")
        regular.listType = "regular"
        XCTAssertTrue(regular.isDomainList)
        XCTAssertFalse(regular.isStatusList)
    }

    func testBothSidebarsFilterWithDomainListPredicate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        for relative in ["Astrid App/Views/Lists/ListSidebarView.swift",
                         "Astrid Mac/App/MacRootView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertTrue(source.contains(".isDomainList"),
                          "\(relative) must filter status rows out of sidebar list sections")
        }
    }
}
