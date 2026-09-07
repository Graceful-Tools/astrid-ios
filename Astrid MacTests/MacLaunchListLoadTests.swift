//  MacLaunchListLoadTests.swift
//  Astrid for Mac — AITD-324: the launch list pull, and where the list cache is written.
//
//  `MacRootView`'s `.task` called `ListService.fetchLists()` at launch, after `startSession()`
//  had already run `performFullSync(includeUserTasks: true)` — which fetches the same collection.
//  It looked like a redundant round trip, but it was not: `performFullSync` assigns
//  `listService.lists` and persists NOTHING, and `fetchLists()` was the only thing in the app that
//  wrote lists to CoreData and pruned the ones the server had stopped returning. Deleting the
//  launch call on its own would have left the Mac's offline sidebar frozen at whatever the last
//  view that happened to call `fetchLists()` had cached, and would have resurrected lists deleted
//  on web at every launch (task 53071260).
//
//  So the caching moved to where the fetching already happens. These pin the guarantee at its new
//  home, and pin the offline-only path — the case the removed line was kept alive to serve.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacLaunchListLoadTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()    // Astrid MacTests
        .deletingLastPathComponent()    // repo root

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - The full sync is what caches now

    func testTheFullSyncCachesTheListCollectionItFetched() throws {
        let sync = try source("Astrid App/Core/Services/SyncManager.swift")
        XCTAssertTrue(sync.contains("cacheListsLocally"),
                      "performFullSync must cache the lists it fetched, or nothing writes the "
                      + "offline list cache once the launch fetch is gone (AITD-324)")
    }

    func testTheLaunchTaskNoLongerRefetchesLists() throws {
        let root = try source("Astrid Mac/App/MacRootView.swift")
        let lines = root.components(separatedBy: .newlines)

        // The launch `.task` is the one that seeds the memoized sidebar badges.
        let start = try XCTUnwrap(lines.firstIndex { $0.contains("myTasksCount = MacMyTasks.filter") })
        let end = try XCTUnwrap(lines[start...].firstIndex { $0.hasSuffix("        }") })

        for line in lines[start...end] {
            XCTAssertFalse(line.contains("fetchLists()"),
                           "the full sync already fetched every list at launch (AITD-324)")
        }
    }

    // MARK: - The offline-only path, which is why the line survived AITD-315

    /// Local-only mode never reaches the full sync — `startSession()` returns before it. Its lists
    /// come from `ListService.init()`, which loads the CoreData cache SYNCHRONOUSLY so they are in
    /// memory before any view body runs. That is the guarantee the removed fetch was standing in
    /// for, and it is unaffected by removing it.
    func testTheOfflineOnlyPathGetsItsListsFromTheSynchronousCacheLoad() throws {
        let gate = try source("Astrid Mac/App/MacAuthGateView.swift")
        XCTAssertTrue(gate.contains("currentMode != .offlineOnly"),
                      "startSession() still skips the network services in local-only mode")

        let service = try source("Astrid App/Core/Services/ListService.swift")
        let lines = service.components(separatedBy: .newlines)
        let initStart = try XCTUnwrap(lines.firstIndex { $0.contains("private init()") })
        let initEnd = try XCTUnwrap(lines[(initStart + 1)...].firstIndex { $0 == "    }" })

        XCTAssertTrue(lines[initStart...initEnd].contains { $0.contains("loadCachedLists()") },
                      "local-only mode has no other list load — init() must still fill the cache")
    }

    func testTheCacheLoadStaysSynchronousSoTheSidebarIsNeverEmptyOnAnOfflineLaunch() throws {
        let service = try source("Astrid App/Core/Services/ListService.swift")
        let lines = service.components(separatedBy: .newlines)
        let start = try XCTUnwrap(lines.firstIndex { $0.contains("private func loadCachedLists()") })

        XCTAssertFalse(lines[start].contains("async"),
                       "an async cache load renders the sidebar empty first (AITD-324)")
    }
}
#endif
