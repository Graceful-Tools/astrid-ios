//  MacQuickAddPlacementGuardTests.swift
//  Regression guard for AITD-300 — "[MAC] In Mac app move Add a task to top of the list (not
//  bottom)".
//
//  `MacAddTaskBar.placement` states the rule; this pins that the layout actually follows it. The
//  Mac list column is one `VStack` in `MacRootView.taskTable`, so "top" is simply "the quick-add
//  card is emitted before the rows" — which is exactly the kind of ordering a refactor swaps
//  without noticing. Lives in the iOS test target because it reads the repo tree, which the
//  sandboxed Mac test host cannot (see MacHardcodedStringGuardTests).

import XCTest

final class MacQuickAddPlacementGuardTests: XCTestCase {

    private func rootSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/App/MacRootView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Inside `taskTable`, the quick-add bar must come BEFORE the rows (and before the empty
    /// state), not after them.
    func testAITD300_ListColumnEmitsTheQuickAddBeforeTheRows() throws {
        let source = try rootSource()
        guard let start = source.range(of: "private var taskTable: some View {") else {
            return XCTFail("MacRootView.taskTable not found")
        }
        // The next property/func declaration ends the block we care about.
        let tail = source[start.upperBound...]
        let end = tail.range(of: "\n    private var listColumn")?.lowerBound ?? tail.endIndex
        let block = String(tail[..<end])

        guard let bar = block.range(of: "quickAddBar"),
              let rows = block.range(of: "taskTableBody(rows)") else {
            return XCTFail("taskTable must render both quickAddBar and taskTableBody(rows)")
        }
        XCTAssertLessThan(bar.lowerBound, rows.lowerBound,
                          "the quick-add bar is emitted after the rows — it is back at the bottom of the list")
        XCTAssertTrue(block.contains("MacAddTaskBar.placement"),
                      "the layout should follow the placement rule rather than restate it")
    }
}
