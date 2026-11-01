//  PublicListBrowseTests.swift
//  AITD-573: a public list you do not belong to is read by `?listId=`, never from the sync cache.

import XCTest
@testable import Astrid_App

final class PublicListBrowseTests: XCTestCase {

    private func task(_ id: String, list: String, creator: String? = nil, assignee: String? = nil) -> Task {
        var t = Task(id: id, title: id)
        t.listIds = [list]
        t.creatorId = creator
        t.assigneeId = assignee
        return t
    }

    /// AITD-573: an `astrid://lists/<id>` link opened TaskListView as one of YOUR lists, which
    /// draws from the sync cache. That cache held a stranger's public list only because the
    /// no-`listId` read ORed in every PUBLIC list — the clause web AWTD-1451 removes. A list
    /// that is not yours has to open the way the featured browser opens it: fetched by id.
    func test_AITD573_aLinkToAListThatIsNotYoursOpensItAsABrowse() {
        let yours = [TaskList(id: "mine", name: "Mine")]
        XCTAssertTrue(TaskListRows.browsesFromServer(listId: "strangers", yourLists: yours),
                      "AITD-573: a list you neither own nor belong to is fetched by ?listId=")
        XCTAssertFalse(TaskListRows.browsesFromServer(listId: "mine", yourLists: yours),
                       "your own list still draws from the cache, offline included")
    }

    /// Before any list has loaded there is nothing to tell yours from theirs: open from the cache,
    /// as before, rather than treat your own list as a stranger's.
    func test_AITD573_withNoListsLoadedALinkOpensFromTheCache() {
        XCTAssertFalse(TaskListRows.browsesFromServer(listId: "any", yourLists: []))
    }

    /// AITD-573: a deep link (`astrid.cc/lists/<id>`) to someone else's public list opens it as
    /// the featured browser does.
    @MainActor
    func test_AITD573_aDeepLinkToAListThatIsNotYoursOpensAsAPublicList() {
        let presenter = ListPresenter.shared
        defer { presenter.clearNavigation(); presenter.isShowingFeaturedList = false }
        let yours = [TaskList(id: "mine", name: "Mine")]
        presenter.showList(listId: "strangers", yourLists: yours)
        XCTAssertTrue(presenter.isShowingFeaturedList, "AITD-573: fetched by ?listId=, not the cache")
        presenter.showList(listId: "mine", yourLists: yours)
        XCTAssertFalse(presenter.isShowingFeaturedList)
    }

    /// The merge the browse draws: your cached tasks (they may carry unsent edits) plus the
    /// others the fetch brought.
    func test_AITD573_theBrowseIsYourCachedTasksPlusTheFetch() {
        let cached = task("yours", list: "pub", assignee: "me")
        var serverCopy = cached; serverCopy.title = "server copy"
        let theirs = task("theirs", list: "pub", creator: "them")
        let rows = TaskListRows.mergeFeatured(tasks: [cached], featuredListTasks: [serverCopy, theirs],
                                              listId: "pub", currentUserId: "me")
        XCTAssertEqual(rows.map(\.id), ["yours", "theirs"])
        XCTAssertEqual(rows.first?.title, "yours")
    }
}
