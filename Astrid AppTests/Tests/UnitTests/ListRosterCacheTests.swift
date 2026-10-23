//  ListRosterCacheTests.swift
//  Regression guard for AITD-413 — "[iOS] Cannot assign tasks when offline".
//
//  A list rehydrated from CoreData used to come back with no `owner` and no `listMembers`,
//  because `CDTaskList` never persisted either. The assignee picker (the core's `assigneeOptions`) builds its
//  roster from exactly those two fields, so after an offline cold launch the picker had nobody
//  in it. This is the store that keeps them.

import XCTest
@testable import Astrid_App

final class ListRosterCacheTests: XCTestCase {

    /// A roster as an older build wrote it into `CDTaskList.listRosterJSON`, which the one-time
    /// seed still reads: who the list knows survives, with names intact — an id alone would put a
    /// bare uuid where a person's name belongs in the picker.
    func testAStoredRosterDecodesWithItsPeopleNamed() {
        let stored = """
        {"owner":{"id":"jon","email":"jon@astrid.cc","name":"Jon"},
         "members":[{"id":"lm-dana","listId":"list-1","userId":"dana","role":"MEMBER",
                     "user":{"id":"dana","email":"dana@astrid.cc","name":"Dana"}}]}
        """

        let restored = ListRosterCache.decode(stored)

        XCTAssertEqual(restored.owner?.id, "jon")
        XCTAssertEqual(restored.owner?.name, "Jon")
        XCTAssertEqual(restored.members?.map(\.userId), ["dana"])
        XCTAssertEqual(restored.members?.first?.user?.name, "Dana",
                       "the hydrated user is the part the picker needs — a userId cannot be shown")
    }

    func testGarbageDecodesToAnEmptyRosterRatherThanThrowing() {
        XCTAssertNil(ListRosterCache.decode("not json").owner)
        XCTAssertNil(ListRosterCache.decode(nil).members)
    }
}
