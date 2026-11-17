//  SidebarListPresentationTests.swift
//  ADEV-60 design review: Favorites in the person's order on iPhone, iPad and Mac alike.

import XCTest
@testable import Astrid_App

final class SidebarListPresentationTests: XCTestCase {

    private func favorite(_ id: String, order: Int?) -> TaskList {
        var list = TestHelpers.createTestList(id: id, name: id)
        list.isFavorite = true
        list.favoriteOrder = order
        list.listType = "regular"
        return list
    }

    func testFavoritesFollowTheOrderThePersonSetNotTheirNames_ADEV60() {
        let lists = [favorite("a", order: 2), favorite("b", order: 0), favorite("c", order: nil), favorite("d", order: 1)]
        XCTAssertEqual(SidebarFavorites.ordered(lists).map(\.id), ["b", "d", "a", "c"])
    }

    func testOnlyFavoriteDomainListsAreFavorites_ADEV60() {
        var notFavorite = TestHelpers.createTestList(id: "x", name: "x")
        notFavorite.isFavorite = false
        var status = favorite("s", order: 0)
        status.listType = "status"
        XCTAssertEqual(SidebarFavorites.ordered([notFavorite, status, favorite("f", order: 0)]).map(\.id), ["f"])
    }
}
