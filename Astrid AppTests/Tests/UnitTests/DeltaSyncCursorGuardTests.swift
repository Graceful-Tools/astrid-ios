//  DeltaSyncCursorGuardTests.swift
//  AITD-427 — "Confirm the app never sends an updatedSince cursor older than 30 days."
//
//  The answer, verified 2026-09-23: it never sends one AT ALL, so there is no age to cap.
//  These tests exist so that stays true, because the day it stops being true is the day the
//  question becomes a silent data-loss bug rather than a design note.
//
//  WHAT CHANGED ON THE SERVER. Web now expires deletion tombstones (AWTD-993):
//  `DELETION_LOG_RETENTION_DAYS = 30` in `lib/deletion-log.ts` had existed for months with
//  nothing calling `pruneDeletionLog()`, so effective retention was infinite; the nightly
//  cron calls it now, which makes the declared 30 days real.
//
//  WHY THAT WOULD MATTER TO A CURSOR CLIENT. `deletedIds` is attached to a v1 tasks/lists
//  response ONLY when `updatedSince` is present and valid. A client that sends a cursor older
//  than retention gets a delta that no longer mentions rows deleted before the prune window —
//  the row is gone server-side, nothing raises anything, and the local copy stays visible
//  forever. Only a full fetch repairs it. Web's guard is `MAX_CURSOR_AGE = 24h` in
//  `lib/data-sync.ts`, forcing a full sync past that: a 30x margin.
//
//  WHY iOS IS STRUCTURALLY IMMUNE, NOT MERELY UNDER THE LIMIT. `SyncManager` does its delta
//  CLIENT-side over a FULL fetch: `getLists()` and `getAllTasks()` take no cursor, and
//  `getAllTasks` pages through `paginatedFetchAllItems` until the server is exhausted. A
//  remote deletion is then learned by ABSENCE from that set — see
//  `SyncRaceConditionTests.testLocalTaskNotOnServerIsDropped`, which pins that branch, so it
//  is deliberately not re-asserted here. Tombstones and cursor age play no part. This matters
//  more here than on web: an iOS app can sit unlaunched for months, which a browser tab
//  effectively cannot, so a cursor added here would carry a worse worst case than the one web
//  had to cap.
//
//  IF YOU CAME HERE BECAUSE THIS TEST FAILED, the fix is not to delete the check — read the
//  failure message, which says what a cursor has to carry with it.

import XCTest
@testable import Astrid_App

final class DeltaSyncCursorGuardTests: XCTestCase {

    /// Everything that ships. Tests are excluded on purpose: THIS file has to be able to name
    /// the parameter it forbids.
    private static let guardedDirectories = [
        "Astrid App",
        "Astrid Mac",
    ]

    /// The v1 delta cursor, plus the names a future one would most plausibly arrive under. A
    /// guard that pinned only today's spelling would be walked around by a rename.
    private static let cursorParameterNames = [
        "updatedSince",
        "modifiedSince",
        "changedSince",
        "deletedSince",
    ]

    // MARK: - The guard

    func testAITD427_NoRequestCarriesADeltaSyncCursor() throws {
        var violations: [String] = []

        for directory in Self.guardedDirectories {
            let directoryURL = RepositoryLocator.root.appendingPathComponent(directory)
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil),
                "\(directory) is not there — the guard is walking nothing"
            )

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                // Comment lines stripped: a file explaining why a cursor needs a cap must be
                // allowed to name one. A guard a comment can trip is not guarding the code.
                let code = try String(contentsOf: fileURL, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")

                for parameter in Self.cursorParameterNames where code.contains(parameter) {
                    violations.append("\(directory)/\(fileURL.lastPathComponent): \(parameter)")
                }
            }
        }

        XCTAssertEqual(
            violations.sorted(), [],
            "iOS fetches the FULL task and list sets and computes its delta locally, which is "
            + "what makes it immune to web expiring deletion tombstones after 30 days "
            + "(DELETION_LOG_RETENTION_DAYS, AWTD-993). A `deletedIds` array only ships when a "
            + "cursor is sent, so today the app cannot miss a deletion at any age.\n\n"
            + "Sending a cursor changes that. If this is a deliberate move to delta fetches — a "
            + "reasonable thing to want — it needs BOTH halves, and the second is the one that "
            + "gets forgotten:\n"
            + "  1. persist a `lastSync` stamp next to the cursor, and\n"
            + "  2. fall back to a FULL fetch when that stamp is older than a threshold "
            + "comfortably under 30 days — a week, say. Web uses 24h (`MAX_CURSOR_AGE` in "
            + "lib/data-sync.ts); an iOS app can sit unlaunched far longer than a browser tab, "
            + "so err shorter here, not longer.\n"
            + "Then update this guard to assert the cap instead of the absence, and say so on "
            + "AITD-427.\n\n"
            + "Cursor sent from:\n"
            + violations.sorted().joined(separator: "\n")
        )
    }

    // MARK: - The guard on the guard

    /// A guard pointed at a renamed directory passes forever while covering nothing. This is the
    /// failure mode `RepositoryLocator` itself was extracted to fix, so it is worth one test.
    func testAITD427_TheGuardIsActuallyWalkingSource() throws {
        for directory in Self.guardedDirectories {
            let directoryURL = RepositoryLocator.root.appendingPathComponent(directory)
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil),
                "\(directory) does not exist — rename it in guardedDirectories"
            )
            let swiftFiles = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            XCTAssertGreaterThan(swiftFiles.count, 10,
                                 "\(directory) yielded \(swiftFiles.count) Swift files — the scan "
                                 + "is not reaching the source it is meant to guard")
        }
    }

    /// And the sync path really is the full fetch this all rests on. If someone swaps
    /// `getAllTasks()` for a delta call, the parameter guard above catches the cursor — but only
    /// if the cursor is spelled one of the four ways it knows. This catches the swap itself.
    func testAITD427_TheIncrementalPassFetchesEverything() throws {
        let syncManager = try RepositoryLocator.source(at: "Astrid App/Core/Services/SyncManager.swift")
        XCTAssertTrue(syncManager.contains("apiClient.getAllTasks()"),
                      "the incremental pass must fetch the full task set and diff locally; a "
                      + "server-side delta would depend on tombstones that now expire (AITD-427)")
        XCTAssertTrue(syncManager.contains("apiClient.getLists()"),
                      "same for lists — /api/v1/lists attaches deletedIds only to a cursored request")
    }
}
