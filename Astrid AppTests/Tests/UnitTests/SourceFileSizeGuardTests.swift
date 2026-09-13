//  SourceFileSizeGuardTests.swift
//  Task AITD-346 — nine production files are over 1,000 lines; in August it was six.
//
//  This is a RATCHET, not a refactor. The August hygiene review
//  (`docs/HYGIENE_REVIEW_2026-08.md`, finding 3) listed six files over 1,000 lines and concluded
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
        // Was 2090. AITD-363 extracted the leading control into its own
        // `TaskDetailLeadingControl.swift` — the shape the Mac has had since
        // `MacLeadingControlButton` — rather than raising this to fit a confirmation
        // dialog into the largest file in the repo. The ratchet asked the question and
        // the answer was an extraction; the new number is what stops the lines coming back.
        "Astrid App/Views/Tasks/TaskDetailViewNew.swift": 1914,
        "Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift": 1822,
        "Astrid App/Views/Tasks/TaskListView.swift": 1766,
        "Astrid App/Core/Services/TaskService.swift": 1675,
        // Was 1674. AITD-387 lifted the quick-add options popover out into
        // `MacDraftDefaultsPicker` so the global ⌥Space window could offer the same
        // choices instead of a second copy of them. Locking in what that removed.
        "Astrid Mac/App/MacRootView.swift": 1660,
        // Was 1625, then 1639, and the second raise in one day is what this ratchet exists to
        // catch — the question it asks is "should this still be one file?", and for a coherent
        // group of six member/invitation endpoints the answer was no. AITD-388 moved them to
        // `AstridAPIClient+ListMembers.swift`, so the number goes DOWN rather than up again.
        "Astrid App/Core/Networking/AstridAPIClient.swift": 1578,
        "Astrid App/Core/Sync/GoogleTasksSyncService.swift": 1240,
        "Astrid App/Core/Services/AppleRemindersService.swift": 1061,
        "Astrid App/Views/Tasks/QuickAddTaskView.swift": 1042,
    ]

    /// How far below its ceiling a file may sit before the ceiling should be tightened. Without
    /// this the list only ever ratchets UP: a file could be split in half and its old ceiling
    /// would happily readmit every line that was removed.
    private static let slack = 150

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every production Swift file, keyed by repo-relative path, with its line count.
    private func lineCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for root in Self.roots {
            let rootURL = repositoryRoot.appendingPathComponent(root)
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
