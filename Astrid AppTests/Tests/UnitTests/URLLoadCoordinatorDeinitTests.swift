//  URLLoadCoordinatorDeinitTests.swift
//  Regression guard for the Release-build crash found while adding the local App Store release
//  path (`npm run release:ios` / `release:mac`, 2026-08-23).
//
//  `URLLoadCoordinator` is a generic `@MainActor` class holding a dictionary of `Task`s. With the
//  compiler-synthesized deinit, Swift 6.3.3 crashes in `EarlyPerfInliner` on that deinit whenever
//  the file is compiled with `-O` — reproducible in three lines of swiftc for both the macOS and
//  iOS targets, and fatal to `xcodebuild archive`, which always builds Release. Nothing catches it
//  in a Debug build or a normal test run, so it reached HEAD unnoticed and blocked every Mac
//  archive. Writing the deinit by hand avoids the crashing path.
//
//  Note what these tests can and cannot do. The crash is a COMPILE-time event under `-O`; no
//  XCTest can observe it, and the real guard is any Release archive (`npm run release:mac
//  --dry-run`). What is asserted here is that the hand-written deinit is correct and actually
//  runs: coalescing still behaves, and the coordinator still deallocates once its callers are
//  done. The cancellation in the deinit is deliberately not asserted — a caller awaiting `load`
//  holds the coordinator alive for the whole load, so `inFlight` is empty by the time deinit
//  runs; the loop is defensive, for any future caller that abandons a load.

import XCTest
@testable import Astrid_App

@MainActor
final class URLLoadCoordinatorDeinitTests: XCTestCase {

    private let url = URL(string: "https://example.test/images/slow.png")!

    /// The deinit runs and releases the coordinator — the path that used to crash the optimizer.
    func testCoordinatorDeallocatesAfterLoading() async {
        weak var weakCoordinator: URLLoadCoordinator<Int>?

        do {
            let coordinator = URLLoadCoordinator<Int>()
            weakCoordinator = coordinator
            let value = await coordinator.load(for: url) { 7 }
            XCTAssertEqual(value, 7)
        }

        XCTAssertNil(weakCoordinator, "The coordinator should be released once its loads are done")
    }

    /// The behaviour the type exists for, unchanged by the deinit: simultaneous requests for one
    /// URL share a single operation instead of each starting their own (AITD-283).
    func testSimultaneousLoadsForOneURLShareOneOperation() async {
        let coordinator = URLLoadCoordinator<Int>()
        var operationCount = 0

        let operation: @MainActor () async -> Int? = {
            operationCount += 1
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
            return 42
        }

        async let first = coordinator.load(for: url, operation: operation)
        async let second = coordinator.load(for: url, operation: operation)
        let results = await [first, second]

        XCTAssertEqual(results, [42, 42])
        XCTAssertEqual(operationCount, 1, "The second caller should await the first fetch")
    }
}
