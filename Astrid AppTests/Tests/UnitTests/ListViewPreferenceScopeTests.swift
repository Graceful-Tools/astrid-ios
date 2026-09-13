//  ListViewPreferenceScopeTests.swift
//  Regression guard for Task AITD-394 — "[ios/mac] Sort & filters are per-user now".
//
//  The server moved sort and every filter into a per-user `UserListViewPreference` row keyed
//  (userId, listId) and overlays it onto the list payload on read. The wire contract did not
//  change, so the clients were already correct — but two things about them stopped being true.
//
//  1. The Mac List Settings window printed, above its Sort & Filters tab, that sort and filters
//     "apply to everyone who can see it — not just you". That was accurate when written (it was
//     the interim mitigation filed on AWTD-927) and is now the exact opposite of the truth.
//
//  2. A payload hazard that per-user state turned from cosmetic into data loss. The server writes
//     EVERY view field present in the body to the caller's own preference row. So an editor that
//     round-trips a whole cached `TaskList` for an unrelated edit — renaming the list, changing a
//     default — would write that cache's stale filter values over preferences the user has since
//     changed on another device. Under the old shared columns this flapped a setting everyone saw;
//     now it silently reverts one person's view and looks to them like lost data.
//
//  No client sends a whole object today: every non-view editor builds a delta. That was a
//  convention held up by one code comment, which is what this pins.

import XCTest

final class ListViewPreferenceScopeTests: XCTestCase {

    /// The fields the server now stores per-user. Writing one of these writes the CALLER's view.
    private let viewFields = ["sortBy", "filterPriority", "filterAssignee", "filterDueDate",
                              "filterCompletion", "filterRepeating", "filterAssignedBy",
                              "filterInLists"]

    /// Fields that identify or configure the LIST ITSELF, still shared by everyone who sees it.
    /// A payload carrying one of these is an editor for something other than your view — which is
    /// what makes it a place a view field must not appear.
    ///
    /// `isVirtual` is deliberately NOT here. A saved filter's definition IS its filter fields, so
    /// `SaveFilterDialog` and `MacListFilter` write the two together and are right to.
    private let listIdentityFields = ["name", "description", "color", "imageUrl", "privacy",
                                      "defaultPriority", "defaultDueDate", "defaultAssigneeId"]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }

    // MARK: - 1. The copy

    /// The retired claim must be gone everywhere, and its replacement must exist in every
    /// language — a note that ships in English only is worse than no note, because the eleven
    /// other locales fall back to the key name.
    func testSortAndFilterCopyDoesNotClaimItAppliesToEveryone() throws {
        let localizations = repoRoot.appendingPathComponent("Astrid App/Resources/Localizations")
        let lprojs = try FileManager.default
            .contentsOfDirectory(at: localizations, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertEqual(lprojs.count, 12, "Expected 12 localizations, found \(lprojs.count)")

        var stillShared: [String] = []
        var missingPersonal: [String] = []

        for lproj in lprojs {
            let strings = lproj.appendingPathComponent("Localizable.strings")
            let source = try String(contentsOf: strings, encoding: .utf8)
            let language = lproj.deletingPathExtension().lastPathComponent

            if source.contains("lists.sort_filters_shared_note") {
                stillShared.append(language)
            }
            if !source.contains("\"lists.sort_filters_personal_note\"") {
                missingPersonal.append(language)
            }
        }

        XCTAssertEqual(stillShared, [], """
            lists.sort_filters_shared_note says sort and filters apply to everyone who can see the
            list. They are per-user on the server as of AITD-394 / AWTD-927, so the note is false.
            Still present in: \(stillShared.joined(separator: ", "))
            """)

        XCTAssertEqual(missingPersonal, [], """
            lists.sort_filters_personal_note is missing from: \(missingPersonal.joined(separator: ", "))
            """)
    }

    // MARK: - 2. The payload hazard

    /// A list editor that writes the list's own fields must not also write the caller's view.
    ///
    /// The exemption is a delta guard — `if edited.x != original.x { updates["x"] = … }` — which
    /// is how the two combined settings sheets already do it. A field that is only sent when the
    /// user just changed it cannot carry a stale value.
    func testListEditorsDoNotSmuggleViewFieldsIntoUnrelatedSaves() throws {
        var scanned: [String] = []
        var violations: [String] = []

        for tree in ["Astrid App", "Astrid Mac"] {
            let root = repoRoot.appendingPathComponent(tree)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                return XCTFail("Could not enumerate \(root.path)")
            }

            for case let url as URL in files where url.pathExtension == "swift" {
                let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
                let code = lines.map { $0.trimmingCharacters(in: .whitespaces) }

                // Only editors that write the list itself are in scope. The sort/filter sheets
                // write view fields and nothing else, and are the one place that should.
                let isListEditor = code.contains { line in
                    !line.hasPrefix("//") && listIdentityFields.contains { writesKey($0, in: line) }
                }
                guard isListEditor else { continue }
                scanned.append(url.lastPathComponent)

                for (index, line) in code.enumerated() where !line.hasPrefix("//") {
                    for field in viewFields where writesKey(field, in: line) {
                        guard !isDeltaGuarded(lineAt: index, in: code) else { continue }
                        violations.append("\(url.lastPathComponent):\(index + 1) — \"\(field)\"")
                    }
                }
            }
        }

        XCTAssertFalse(scanned.isEmpty, "Found no list editors to scan — the heuristic has rotted")

        XCTAssertEqual(violations.sorted(), [], """
            These editors send a per-user view field alongside an unrelated list edit. The server
            writes every view field in the body to the caller's preference row, so a stale cached
            value here silently reverts that user's own sort or filters (AITD-394).

            Send only the fields being edited, or guard each one with `if edited.x != original.x`:
            \(violations.sorted().joined(separator: "\n"))
            """)
    }

    /// True when `line` puts `key` INTO an update payload — either `updates["key"] = …` or a
    /// `"key": value` entry in a dictionary literal.
    ///
    /// Reading the same subscript is not a write, and the distinction matters: `ListService`
    /// unpacks every one of these keys as `if let x = updates["sortBy"] as? String` to build its
    /// optimistic list. That is the transport applying a payload, not an editor composing one.
    private func writesKey(_ key: String, in line: String) -> Bool {
        if line.contains("\"\(key)\":") { return true }   // dictionary literal entry

        let subscriptText = "[\"\(key)\"]"
        guard let range = line.range(of: subscriptText) else { return false }
        let rest = line[range.upperBound...].drop { $0 == " " }
        return rest.hasPrefix("=") && !rest.hasPrefix("==")
    }

    /// True when the write is fenced by an inequality against the original — the delta shape.
    /// Looks back past blanks and comments to the `if` that opens the block.
    private func isDeltaGuarded(lineAt index: Int, in code: [String]) -> Bool {
        var cursor = index - 1
        while cursor >= 0 {
            let line = code[cursor]
            if line.isEmpty || line.hasPrefix("//") { cursor -= 1; continue }
            return line.hasPrefix("if ") && line.contains("!=")
        }
        return false
    }
}
