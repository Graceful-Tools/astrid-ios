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

    /// Write methods that reach the server DIRECTLY, with no Outbox to retry them. A swallowed
    /// failure on one of these is gone: nothing queued, nothing retried, nothing said.
    private let directAPIWrites = [
        "createList", "updateList", "updateListAdvanced", "deleteList",
        "addMember", "removeMember", "updateMemberRole",
    ]

    // MARK: - Q1: iOS has a global error surface now

    func testAITD406_TheIOSRootShowsTheSharedErrorBanner() throws {
        let root = try source("AstridApp.swift")
        XCTAssertTrue(root.contains("AppErrorBanner()"),
                      "iOS should present the shared banner at the root, as MacAuthGateView does")
    }

    /// The banner is only useful if the copy is translated. `report` looks the sentence up by the
    /// FIRST WORD of the call-site context, so a context whose verb is not in the map falls back
    /// to the generic line — silently, and only visible to a user in another language.
    func testAITD406_EveryContextThisTaskIntroducesMapsToRealCopy() {
        XCTAssertEqual(FailureCopy.message(for: "Delete list"),
                       NSLocalizedString("mac.failed.delete", comment: ""))
        XCTAssertEqual(FailureCopy.message(for: "Save list settings"),
                       NSLocalizedString("mac.failed.save", comment: ""))
        XCTAssertEqual(FailureCopy.message(for: "Save list filters"),
                       NSLocalizedString("mac.failed.save", comment: ""))
        // And the guard on the guard: an unmapped verb really does fall back, so the three above
        // are asserting something.
        XCTAssertEqual(FailureCopy.message(for: "Frobnicate list"),
                       NSLocalizedString("mac.failed.generic", comment: ""))
    }

    // MARK: - Q2: the three that were saying nothing now speak

    /// Each of these failed a write that reaches the server directly, and told the user nothing —
    /// no message, and no revert either, so the screen went on showing the change that did not
    /// happen. These are the exact bug `AppErrorCenter` was built for.
    func testAITD406_TheThreeSilentListWritesNowReport() throws {
        let taskList = try source("Astrid App/Views/Tasks/TaskListView.swift")
        XCTAssertTrue(taskList.contains(#"AppErrorCenter.shared.report("Delete list""#),
                      "a refused deleteList must say so — the list reappears at the next fetch otherwise")
        XCTAssertTrue(taskList.contains(#"AppErrorCenter.shared.report("Save list settings""#),
                      "the advanced-update catch applied local state and dropped the server write")

        let filters = try source("Astrid App/Views/Lists/ListSortFiltersTab.swift")
        XCTAssertTrue(filters.contains(#"AppErrorCenter.shared.report("Save list filters""#),
                      "this one logged the failure three times and showed the user nothing")
    }

    /// And no NEW silent one appears. Scoped to the direct-API writes on purpose: see below for
    /// why a blanket ban would be wrong on iOS.
    func testAITD406_NoIOSViewSwallowsADirectAPIWrite() throws {
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
                for method in directAPIWrites where code.contains("\(method)(") {
                    violations.append("\(url.lastPathComponent):\(index + 1) — try? await …\(method)(")
                }
            }
        }

        XCTAssertEqual(violations, [], """
            These writes have no Outbox behind them, so a swallowed failure is simply lost. \
            Report through AppErrorCenter instead of `try?`:
            \(violations.joined(separator: "\n"))
            """)
    }

    // MARK: - The anti-sweep guard

    /// THE POINT OF THIS TEST IS TO SAY NO. Someone reading AITD-400's "~45 copies of
    /// `catch { errorMessage = … }`" will reasonably want to convert the task, comment and chat
    /// writes too — there are 36 of them and they look identical to the three above.
    ///
    /// They are not identical. These writes hand off to the Outbox, which is what makes editing
    /// offline work at all: the optimistic value IS the truth, and the server catches up. Routing
    /// them through a transient "Couldn't save your changes" banner would be a lie told to
    /// someone whose edit is safely queued — the noisy outcome Jon asked to avoid.
    ///
    /// If this test ever fails because the Outbox stopped backing one of these, that write becomes
    /// a real candidate for the banner and should be reconsidered. That is the only circumstance
    /// in which the answer above changes.
    func testAITD406_TheWritesDeliberatelyLeftSilentAreTheOutboxBackedOnes() throws {
        let tasks = try source("Astrid App/Core/Services/TaskService.swift")
        for enqueue in ["enqueueCreateTask", "enqueueUpdateTask", "enqueueDeleteTask"] {
            XCTAssertTrue(tasks.contains("OutboxManager.shared.\(enqueue)"),
                          "task writes must stay Outbox-backed — that is why they are not banner-ed")
        }

        let comments = try source("Astrid App/Core/Services/CommentService.swift")
        XCTAssertTrue(comments.contains("Outbox"),
                      "comment writes queue rather than fail; CommentSectionViewEnhanced's silence is correct")

        // The scan above must not reach them, or the reasoning and the guard disagree.
        for outboxBacked in ["createTask", "updateTask", "completeTask", "deleteTask",
                             "createComment", "deleteComment", "sendMessage"] {
            XCTAssertFalse(directAPIWrites.contains(outboxBacked),
                           "\(outboxBacked) is Outbox-backed and must stay out of the silent-write ban")
        }
    }
}
