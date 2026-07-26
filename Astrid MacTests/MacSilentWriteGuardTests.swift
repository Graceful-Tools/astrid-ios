//  MacSilentWriteGuardTests.swift
//  Regression guard for Task f1f0cb13 — "[Mac] Failed writes disappear silently".
//
//  Mac call-sites used `_ = try? await TaskService…`, so a rejected create/update/delete
//  produced no banner, no log, and no rollback — the user saw the optimistic row and assumed
//  it saved. Writes must go through `MacActions.perform`, which reports through MacErrorCenter.
//  Reads (`fetchMembers`, `fetchLists`, `searchContacts`) may still use `try?`: a stale refresh
//  is not a lost edit.

import XCTest

final class MacSilentWriteGuardTests: XCTestCase {

    /// Service methods that MUTATE server state. A swallowed failure here loses user data.
    private let writeMethods = [
        "createTask", "updateTask", "deleteTask", "completeTask",
        "createList", "updateList", "updateListAdvanced", "deleteList",
        "addMember", "removeMember", "updateMemberRole",
        "createComment", "deleteComment", "sendMessage",
        "reorderTasks", "moveTask", "makeSubtask",
    ]

    func testNoMacWriteSwallowsItsError() throws {
        let macRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac")

        guard let files = FileManager.default.enumerator(at: macRoot, includingPropertiesForKeys: nil) else {
            return XCTFail("Could not enumerate \(macRoot.path)")
        }

        var violations: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                // Comments describing the old pattern (MacErrorCenter's header) are not call-sites.
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains("try? await") else { continue }
                for method in writeMethods where code.contains("\(method)(") {
                    violations.append("\(url.lastPathComponent):\(index + 1) — try? await …\(method)(")
                }
            }
        }

        XCTAssertEqual(violations, [], """
            Mac writes must surface failures via MacActions.perform, not swallow them with `try?`:
            \(violations.joined(separator: "\n"))
            """)
    }
}
