//  SourceFileSizeGuardTests.swift
//  Task AITD-346 — nine production files are over 1,000 lines; in August it was six.
//
//  This is a RATCHET, not a refactor. The August hygiene review
//  (`docs/archive/HYGIENE_REVIEW_2026-08.md`, finding 3) listed six files over 1,000 lines and concluded
//  "small extractions, one per change, not a restructure". Three weeks later all four of the
//  biggest had grown and three more had crossed — because nothing was watching. Every individual
//  addition was reasonable; the drift was the sum of them, and nobody was in a position to see
//  the sum.
//
//  So: no file may cross 1,000 lines, except the ones that already have, and those may not grow
//  past what they measured on 2026-09-07. Growing one is then a deliberate act — you have to come
//  here and raise the number, which is exactly the moment to ask whether an extraction would be
//  better. Extractions get filed per file as they come up.
//
//  Tests are excluded. A long test file is usually many small cases, which is not the problem
//  this guards.

import XCTest

final class SourceFileSizeGuardTests: XCTestCase {

    /// Production source roots. Test targets are deliberately absent.
    private static let roots = ["Astrid App", "Astrid Mac", "Astrid"]

    /// What a file is allowed to be if it has not already crossed.
    private static let threshold = 1_000

    /// Files already over the line on 2026-09-07, at the length they were then.
    ///
    /// Lowering an entry is always welcome. RAISING one should be a conscious decision with a
    /// reason, not a reflex to make the suite green — that reflex is how six became nine.
    private static let ceilings: [String: Int] = [
        // Was 2090, then 1914. AITD-363 extracted the leading control into its own
        // `TaskDetailLeadingControl.swift` — the shape the Mac has had since
        // `MacLeadingControlButton` — rather than raising this to fit a confirmation
        // dialog into the largest file in the repo. The ratchet asked the question and
        // the answer was an extraction; the new number is what stops the lines coming back.
        //
        // It asked again on AITD-425, which needed ~14 lines to give the back chevron a 44pt
        // tap target, and got the same answer: the custom header was 109 lines of four
        // controls with no state of their own beyond the parent's, so it moved to
        // `TaskDetailHeaderBar.swift`. Down to 1836, not up to 1928 — which is the whole
        // point of asking.
        "Astrid App/Views/Tasks/TaskDetailViewNew.swift": 1836,
        "Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift": 1822,
        // Was 1766. The 2026-09-13 dedupe pass moved the task read-only / can-add rules into
        // `ListPermissions`, where the Mac and web already look for them.
        // Briefly 1725 while AITD-406 added error reporting, then DOWN to 1640: AITD-409 took
        // the ratchet's question seriously and moved the ~85-line settings diff out to
        // `ListSettingsPayload`, where it is a pure function with tests instead of a wall of
        // near-identical `if`s inside the third-largest file in the repo. That wall is where the
        // "Recently completed" field went missing for a while (545812e6), which is the argument
        // for the extraction better than any line count is.
        "Astrid App/Views/Tasks/TaskListView.swift": 1640,
        // Was 1674. AITD-410 added a 3-line `mappedRealListId` accessor so the `updateList`
        // Outbox handler can retarget a queued settings change from an offline-created list's
        // temp id onto the real one. The ratchet's question was asked and answered: the
        // alternative was a SECOND temp→real list map owned by ListService, duplicating the one
        // `onListSynced` already maintains here — more lines overall, in two places that could
        // disagree. Nothing else in this file grew.
        //
        // Then 1683 → 1691 for AITD-415, which rejoins cached tasks with their lists on the way
        // out of CoreData. The ratchet asked and the answer was a partial extraction: the three
        // cache-load paths each repeated the same filter-map pair, so they now share
        // `tasksFromCache`, and the lists lookup moved to `CDTaskList.cachedDomainModels`. That
        // is why +8 and not +20. A FULL extraction — moving the whole cache-load block to a
        // `TaskService+CacheLoad.swift` extension, the way AITD-388 moved the list-member
        // endpoints out of AstridAPIClient — was measured and rejected: the block needs four
        // `private` members (`cachedTasks`, `coreDataManager`, `recentlyDeletedIds`,
        // `updatePendingOperationsCount`), and Swift would make every one of them internal to
        // the whole app target. Widening the invariant-bearing task cache to buy back 8 lines is
        // the wrong trade. Worth revisiting if this file needs extracting for its own sake.
        "Astrid App/Core/Services/TaskService.swift": 1691,
        // Was 1674. AITD-387 lifted the quick-add options popover out into
        // `MacDraftDefaultsPicker` so the global ⌥Space window could offer the same
        // choices instead of a second copy of them, and this was set to 1660 to lock that
        // in. AITD-389 then needed three lines of it back to explain why a real list's sort
        // outranks the window override — 1660 was a tighter number than the extraction had
        // actually earned. Still well below where the day started.
        "Astrid Mac/App/MacRootView.swift": 1663,
        // Was 1625, then 1639, and the second raise in one day is what this ratchet exists to
        // catch — the question it asks is "should this still be one file?", and for a coherent
        // group of six member/invitation endpoints the answer was no. AITD-388 moved them to
        // `AstridAPIClient+ListMembers.swift`, so the number goes DOWN rather than up again.
        // Was 1578. Two methods nothing called (getList, getAvailableModels) left on 2026-09-13.
        "Astrid App/Core/Networking/AstridAPIClient.swift": 1559,
        "Astrid App/Core/Sync/GoogleTasksSyncService.swift": 1233,
        "Astrid App/Core/Services/AppleRemindersService.swift": 1061,
        "Astrid App/Views/Tasks/QuickAddTaskView.swift": 1042,
    ]

    /// How far below its ceiling a file may sit before the ceiling should be tightened. Without
    /// this the list only ever ratchets UP: a file could be split in half and its old ceiling
    /// would happily readmit every line that was removed.
    private static let slack = 150

    /// Every production Swift file, keyed by repo-relative path, with its line count.
    private func lineCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for root in Self.roots {
            let rootURL = RepositoryLocator.root.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: rootURL,
                                                              includingPropertiesForKeys: nil)
            else { continue }
            for case let fileURL as URL in walker where fileURL.pathExtension == "swift" {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                // `wc -l` counts newlines, and that is the number in the review and in `ceilings`.
                counts["\(root)/\(relativePath(of: fileURL, under: rootURL))"] =
                    source.reduce(into: 0) { total, character in
                        if character == "\n" { total += 1 }
                    }
            }
        }
        return counts
    }

    private func relativePath(of file: URL, under root: URL) -> String {
        String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    // MARK: - The ratchet

    func testNoFileGrowsPastItsRecordedCeiling() throws {
        let counts = try lineCounts()
        var violations: [String] = []

        for (path, lines) in counts.sorted(by: { $0.key < $1.key }) {
            let ceiling = Self.ceilings[path] ?? Self.threshold
            if lines > ceiling {
                violations.append("\(path): \(lines) lines, ceiling \(ceiling)")
            }
        }

        XCTAssertEqual(
            violations, [],
            "These files grew past what they are allowed to be (AITD-346). Extract something, or "
            + "raise the ceiling in SourceFileSizeGuardTests deliberately and say why:\n"
            + violations.joined(separator: "\n")
        )
    }

    func testACeilingIsTightenedOnceItsFileHasShrunk() throws {
        let counts = try lineCounts()
        var stale: [String] = []

        for (path, ceiling) in Self.ceilings.sorted(by: { $0.key < $1.key }) {
            guard let lines = counts[path] else { continue }   // covered by the test below
            if lines < ceiling - Self.slack {
                stale.append("\(path): now \(lines) lines but ceiling is still \(ceiling)")
            }
        }

        XCTAssertEqual(
            stale, [],
            "Good news, and the ratchet needs turning: lower these ceilings to the current counts "
            + "so the lines that were removed cannot quietly come back:\n"
            + stale.joined(separator: "\n")
        )
    }

    /// A ceiling naming a file that no longer exists is an exemption for nothing, and it hides
    /// the case where the file was RENAMED — under its new name it would be held to 1,000 lines
    /// it is nowhere near, and the guard would fail with a confusing message instead of this one.
    func testEveryCeilingNamesAFileThatExists() throws {
        let counts = try lineCounts()
        let missing = Self.ceilings.keys.filter { counts[$0] == nil }.sorted()
        XCTAssertEqual(missing, [],
                       "these ceilings name files that are gone — delete or rename the entries:\n"
                       + missing.joined(separator: "\n"))
    }

    /// The walk has to be finding real code, or every assertion above is vacuously true.
    func testTheWalkActuallyFindsTheSourceTree() throws {
        let counts = try lineCounts()
        XCTAssertGreaterThan(counts.count, 200,
                             "only \(counts.count) Swift files found — the roots are wrong and "
                             + "this guard is checking nothing")
        for root in Self.roots {
            XCTAssertTrue(counts.keys.contains { $0.hasPrefix("\(root)/") },
                          "\(root) contributed no files")
        }
    }
}
