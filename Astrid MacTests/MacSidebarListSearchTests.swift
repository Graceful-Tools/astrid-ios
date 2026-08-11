//  MacSidebarListSearchTests.swift
//  Regression guard for Task 1b0f034d — "[mac] remove the search for lists from the left side list".
//
//  The sidebar briefly had TWO things called search: the global-task-search row under My Tasks
//  (task 36587d3d) and a list-name filter field pinned above the list in a safe-area inset
//  (task 00145582). They shared the accessibility identifier `sidebar.search`, so the Mac UI
//  test that clicks `sidebar.search`.firstMatch had two candidates — and the field sat higher
//  in the sidebar than the row it meant to hit.
//
//  The filter field is gone. These guards keep it gone, and keep the identifier singular, since
//  a duplicate would make the UI suite fail somewhere far away from the cause.

import XCTest

final class MacSidebarListSearchTests: XCTestCase {

    /// Every `.swift` file under `Astrid Mac`, paired with its source.
    private func macSources() throws -> [(name: String, source: String)] {
        let macRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac")

        guard let files = FileManager.default.enumerator(at: macRoot, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate \(macRoot.path)")
            return []
        }
        var out: [(String, String)] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            out.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    /// `sidebar.search` must identify exactly one control — the global search row.
    func testSidebarSearchIdentifierIsUnique() throws {
        var sites: [String] = []
        for (name, source) in try macSources() {
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains("\"sidebar.search\"") else { continue }
                sites.append("\(name):\(index + 1)")
            }
        }
        XCTAssertEqual(sites.count, 1, """
            `sidebar.search` must identify exactly one control. UI tests click it by \
            firstMatch, so a second one silently retargets them. Found at:
            \(sites.joined(separator: "\n"))
            """)
    }

    /// The list-name filter field itself must not come back into the sidebar.
    func testSidebarHasNoListFilterField() throws {
        var uses: [String] = []
        for (name, source) in try macSources() {
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                if code.contains("MacSidebarSearchField(") || code.contains("listSearch") {
                    uses.append("\(name):\(index + 1) — \(code)")
                }
            }
        }
        XCTAssertEqual(uses, [], """
            The sidebar list-name filter was removed (task 1b0f034d). Lists are filtered by \
            favorite status only:
            \(uses.joined(separator: "\n"))
            """)
    }
}
