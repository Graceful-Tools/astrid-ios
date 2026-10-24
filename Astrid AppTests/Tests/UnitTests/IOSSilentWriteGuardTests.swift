//  IOSSilentWriteGuardTests.swift
//  AITD-406 — "Decide whether iOS should adopt the shared error banner, and which silent catches
//  should speak."
//
//  Jon's answer (2026-09-14): yes to the banner; which catches speak is my recommendation, "but
//  not too noisy". These tests pin where that line ended up AND why, because the why is the part
//  that is easy to lose.
//
//  AITD-400's description suggested a sweep of ~45 silent catches. Running the Mac's own
//  `MacSilentWriteGuardTests` scan over the iOS tree does find 39 — and converting them would be
//  wrong, because on iOS those writes cannot fail the way the banner is for. `TaskService`'s
//  create/update/complete/delete, `CommentService`'s comment writes and `ChatService.sendMessage`
//  are all Outbox-backed: they write optimistically, enqueue, and drain on reconnect. A network
//  failure there is not an error, it is a queued row. Banner-ing them would tell someone editing
//  offline that their edit was lost when it was not.
//
//  What genuinely qualifies is the writes with NO Outbox behind them — list and member writes go
//  straight to the API — at the call sites that neither revert nor say anything.

import XCTest
@testable import Astrid_App

final class IOSSilentWriteGuardTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Writes with no journal behind them that ALSO surface their failure to the caller. A
    /// swallowed failure on one of these is gone: nothing queued, nothing retried, nothing said.
    ///
    /// List writes left this list when lists moved into astrid-core's journal (docs/
    /// CORE_MIGRATION.md): like task writes, they are local-first and a server refusal is a
    /// dead-lettered entry, not a thrown error — see `testListWritesAreTheCoresJournaledWrites`.
    private let throwingDirectAPIWrites = [
        "addMember", "removeMember", "updateMemberRole",
    ]

    // MARK: - Q2: the three that were saying nothing now speak

    /// And no NEW silent one appears. Scoped to the direct-API writes on purpose: see below for
    /// why a blanket ban would be wrong on iOS.
    func testAITD406_NoIOSViewSwallowsAWriteThatReportsItsFailure() throws {
        let views = RepositoryLocator.root.appendingPathComponent("Astrid App/Views")
        guard let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil) else {
            return XCTFail("Could not enumerate \(views.path)")
        }

        var violations: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains("try? await") else { continue }
                for method in throwingDirectAPIWrites where code.contains("\(method)(") {
                    violations.append("\(url.lastPathComponent):\(index + 1) — try? await …\(method)(")
                }
            }
        }

        XCTAssertEqual(violations, [], """
            These writes have no Outbox behind them AND they surface the failure to you, \
            so a `try?` here simply loses it. Report through AppErrorCenter instead:
            \(violations.joined(separator: "\n"))
            """)
    }
}
