//  GitHubSyncPassTests.swift
//  One GitHub sync pass end to end (AITD-535): the proxy answered by `StubURLProtocol`, the writes
//  landing in the unit host's in-memory core through TaskService. The planners the pass leans on
//  (SyncSuppression, SyncAdoptionSafety, ProviderCursorCommitter…) have their own tests; these pin
//  the orchestration the 2026-10-22 coverage audit found unexecuted — what a pulled issue becomes,
//  what a local task pushes, that the pulled cursor is committed only after the pass applied, and
//  how comments converge on a linked task: pulled, deleted and edited in each direction.

import XCTest
@testable import Astrid_App

@MainActor
final class GitHubSyncPassTests: XCTestCase {
    private let repo = "octo/repo"
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var service: GitHubSyncService!
    private var tasks: TaskService { TaskService.shared }

    /// What the proxy answers, by route. A test overrides the routes it cares about.
    private var taskLinks: [[String: Any]] = []
    private var pulledItems: [[String: Any]] = []
    private var pulledCursor = "cursor-2"
    private var fullItems: [[String: Any]] = []
    private var fullTruncated = false
    private var upsertStatus = 200
    private var remoteComments: [[String: Any]] = []
    private var commentsStatus = 200

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
        suiteName = "GitHubSyncPassTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = GitHubSyncService(apiClient: AstridAPIClient(session: StubURLProtocol.session()),
                                    defaults: defaults)
        taskLinks = []; pulledItems = []; fullItems = []
        pulledCursor = "cursor-2"; fullTruncated = false; upsertStatus = 200
        remoteComments = []; commentsStatus = 200
    }

    override func tearDown() async throws {
        service.isConnected = false
        service.links = []
        StubURLProtocol.reset()
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    // MARK: Fixture

    private func name(_ base: String) -> String { "\(base) \(UUID().uuidString)" }

    /// A task the server has already given its id. One created here stays `temp_` — the unit host
    /// is offline — and the push leaves those for the Outbox, so the push side needs this instead.
    private func serverTask(in listId: String, title: String) -> Task {
        let task = TestHelpers.createTestTask(id: "server-\(UUID().uuidString)", title: title,
                                              listIds: [listId], updatedAt: Date())
        tasks.adoptForTesting(task)
        return task
    }

    private func iso(_ date: Date) -> String { WireDate.string(from: date) }

    private func issue(_ number: Int, title: String, notes: String? = nil, completed: Bool = false,
                       updatedAt: Date = Date().addingTimeInterval(60), commentCount: Int? = nil) -> [String: Any] {
        var item: [String: Any] = ["remoteId": "\(repo)#\(number)", "title": title,
                                   "completed": completed, "remoteUpdatedAt": iso(updatedAt)]
        if let notes { item["notes"] = notes }
        if let commentCount { item["metadata"] = ["commentCount": "\(commentCount)"] }
        return item
    }

    private func link(task: String, issue number: Int, syncedAt: Date,
                      commentMap: [CommentSyncPlanner.MapEntry] = []) -> [String: Any] {
        var link: [String: Any] = ["astridTaskId": task, "remoteId": "\(repo)#\(number)", "remoteContainerId": repo,
                                   "astridUpdatedAt": iso(syncedAt), "remoteUpdatedAt": iso(syncedAt)]
        if !commentMap.isEmpty { link["metadata"] = ["commentMap": CommentSyncPlanner.encodeEntries(commentMap)] }
        return link
    }

    nonisolated private static func json(_ object: Any, status: Int = 200) -> StubURLProtocol.Answer {
        .http(status: status, body: try! JSONSerialization.data(withJSONObject: object),
              headers: ["Content-Type": "application/json"])
    }

    /// Route the proxy, then run one pass over a link to `listId`.
    private func runPass(listId: String) async {
        // The stub answers off the main actor, so it reads a snapshot, never `self`.
        let (repo, taskLinks, pulledItems, pulledCursor) = (repo, taskLinks, pulledItems, pulledCursor)
        let (fullItems, fullTruncated, upsertStatus) = (fullItems, fullTruncated, upsertStatus)
        let (remoteComments, commentsStatus) = (remoteComments, commentsStatus)
        let json = Self.json
        let read = Self.read
        let now = WireDate.string(from: Date())
        StubURLProtocol.respond = { request in
            let path = request.url?.path ?? ""
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let body = (request.httpBody ?? request.httpBodyStream.flatMap(read))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            switch (request.httpMethod ?? "", path) {
            case ("GET", "/api/v1/sync/github/task-links"):
                return json(["links": taskLinks], 200)
            case ("PUT", "/api/v1/sync/github/task-links"):
                return json(["link": ["astridTaskId": body["astridTaskId"] ?? "",
                                      "remoteId": body["remoteId"] ?? "",
                                      "remoteContainerId": repo]], upsertStatus)
            case ("GET", "/api/v1/sync/github/issues"):
                if query.contains(where: { $0.name == "full" }) {
                    return json(["items": fullItems, "cursor": NSNull(), "truncated": fullTruncated], 200)
                }
                return json(["items": pulledItems, "cursor": pulledCursor], 200)
            case ("POST", "/api/v1/sync/github/issues"):
                if body["action"] as? String == "commitCursor" { return json(["ok": true], 200) }
                return json(["remoteId": "\(repo)#900", "remoteUpdatedAt": now], 200)
            case ("GET", "/api/v1/sync/github/comments"):
                return json(["comments": remoteComments], commentsStatus)
            case ("POST", "/api/v1/sync/github/comments"):
                return json(["id": "gh-new"], 200)
            case ("PATCH", "/api/v1/sync/github/comments"):
                return json(["id": body["commentId"] ?? ""], 200)
            case ("DELETE", "/api/v1/sync/github/comments"):
                return json(["success": true], 200)
            default:
                return json([String: Any](), 404)
            }
        }
        service.isConnected = true
        service.links = [ExternalListLinkDTO(id: "link-1", astridListId: listId, remoteContainerId: repo,
                                             remoteContainerName: nil, cursor: nil)]
        await service.syncAll()
    }

    nonisolated private static func read(_ stream: InputStream) -> Data? {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private var cursorCommits: [String] {
        StubURLProtocol.requests.filter { $0.method == "POST" && $0.jsonBody?["action"] as? String == "commitCursor" }
            .compactMap { $0.jsonBody?["cursor"] as? String }
    }

    private var issueCreates: [StubURLProtocol.Recorded] {
        StubURLProtocol.requests.filter {
            $0.method == "POST" && $0.path == "/api/v1/sync/github/issues"
                && $0.jsonBody?["action"] == nil && $0.jsonBody?["remoteId"] == nil
        }
    }

    private var linkUpserts: [[String: Any]] {
        StubURLProtocol.requests.filter { $0.method == "PUT" }.compactMap(\.jsonBody)
    }

    private func commentRequests(_ method: String) -> [StubURLProtocol.Recorded] {
        StubURLProtocol.requests.filter { $0.method == method && $0.path == "/api/v1/sync/github/comments" }
    }

    /// The `commentMap` the pass wrote back onto the task's link, if it wrote one.
    private func writtenCommentMap(for taskId: String) -> String? {
        linkUpserts.last { $0["astridTaskId"] as? String == taskId && $0["metadata"] != nil }
            .flatMap { ($0["metadata"] as? [String: Any])?["commentMap"] as? String }
    }

    private func remoteComment(_ id: String, body: String, author: String = "octocat") -> [String: Any] {
        ["id": id, "body": body, "author": author, "createdAt": iso(Date())]
    }

    // MARK: PULL — a linked issue edited on GitHub

    func testALinkedIssueEditedOnGitHubUpdatesTheTaskThenCommitsTheCursor_AITD535() async throws {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        let task = try await tasks.createTask(listIds: [list.id], title: name("Before"))
        taskLinks = [link(task: task.id, issue: 1, syncedAt: Date().addingTimeInterval(-3600))]
        pulledItems = [issue(1, title: "Renamed on GitHub", notes: "Body from GitHub")]
        fullItems = pulledItems

        await runPass(listId: list.id)

        XCTAssertNil(service.lastError)
        XCTAssertEqual(tasks.tasksById[task.id]?.title, "Renamed on GitHub")
        XCTAssertEqual(tasks.tasksById[task.id]?.description, "Body from GitHub")
        XCTAssertTrue(linkUpserts.contains { $0["astridTaskId"] as? String == task.id
            && $0["remoteId"] as? String == "\(repo)#1" }, "the watermark advances on the link")
        XCTAssertEqual(cursorCommits, ["cursor-2"])
        let sent = StubURLProtocol.requests
        let commitIndex = try XCTUnwrap(sent.lastIndex { $0.jsonBody?["action"] as? String == "commitCursor" })
        let upsertIndex = try XCTUnwrap(sent.firstIndex { $0.method == "PUT" })
        XCTAssertLessThan(upsertIndex, commitIndex, "the cursor is acknowledged only after the pass applied")
    }

    func testAnIssueClosedOnGitHubCompletesItsTask_AITD535() async throws {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        let title = name("Close me")
        let task = try await tasks.createTask(listIds: [list.id], title: title)
        taskLinks = [link(task: task.id, issue: 2, syncedAt: Date().addingTimeInterval(-3600))]
        pulledItems = [issue(2, title: title, completed: true)]
        fullItems = pulledItems

        await runPass(listId: list.id)

        XCTAssertEqual(tasks.tasksById[task.id]?.completed, true)
        XCTAssertEqual(cursorCommits, ["cursor-2"])
    }

    /// The pass is only acknowledged when every pulled change landed: a link the server refused to
    /// record leaves the cursor where it was, so the next pass pulls the issue again.
    func testARefusedLinkWriteLeavesTheCursorUncommitted_AITD535() async throws {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        let task = try await tasks.createTask(listIds: [list.id], title: name("Before"))
        taskLinks = [link(task: task.id, issue: 3, syncedAt: Date().addingTimeInterval(-3600))]
        pulledItems = [issue(3, title: "Renamed again")]
        fullItems = pulledItems
        upsertStatus = 500

        await runPass(listId: list.id)

        XCTAssertEqual(tasks.tasksById[task.id]?.title, "Renamed again", "the edit itself still applies")
        XCTAssertEqual(cursorCommits, [], "a pass that did not fully apply is not acknowledged")
    }

    // MARK: PULL — issues with no task yet

    func testANewOpenIssueBecomesATaskInTheLinkedListAndAClosedOneIsNotImported_AITD535() async throws {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        let open = name("Opened on GitHub")
        let closed = name("Closed long ago")
        pulledItems = [issue(10, title: open, notes: "from the issue"), issue(11, title: closed, completed: true)]
        fullItems = pulledItems

        await runPass(listId: list.id)

        let inList = tasks.tasks.filter { ($0.listIds ?? []).contains(list.id) }
        let created = try XCTUnwrap(inList.first { $0.title == open }, "the open issue was imported")
        XCTAssertEqual(created.description, "from the issue")
        XCTAssertFalse(inList.contains { $0.title == closed && !$0.completed },
                       "a closed issue is never imported as an open task")
        // Offline the new task keeps its temp id, and the link row's foreign key needs the real
        // one: writing it anyway would fail silently and the next pass would import a duplicate.
        XCTAssertFalse(linkUpserts.contains { $0["remoteId"] as? String == "\(repo)#10" },
                       "no link is written against a temp id")
        XCTAssertEqual(cursorCommits, [], "so the pass is not acknowledged and the issue comes back next pass")
    }

    // MARK: PUSH — a local task with no issue yet

    func testALocalTaskWithNoTwinCreatesAnIssueAndRecordsTheLink_AITD535() async throws {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        let title = name("Written in Astrid")
        let task = serverTask(in: list.id, title: title)

        await runPass(listId: list.id)

        let create = try XCTUnwrap(issueCreates.first, "the issue is created")
        XCTAssertEqual(create.jsonBody?["title"] as? String, title)
        XCTAssertEqual(create.jsonBody?["linkId"] as? String, "link-1")
        XCTAssertTrue(linkUpserts.contains { $0["astridTaskId"] as? String == task.id
            && $0["remoteId"] as? String == "\(repo)#900" }, "the new issue is linked to the task")
    }

    /// A task whose link row was lost is re-linked to its same-title issue, not pushed as a duplicate.
    func testALocalTaskWithASameTitleIssueLinksToItInsteadOfDuplicating_AITD535() async throws {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        let title = name("Lost its link")
        let task = serverTask(in: list.id, title: title)
        fullItems = [issue(20, title: title)]

        await runPass(listId: list.id)

        XCTAssertTrue(issueCreates.isEmpty, "no duplicate issue")
        XCTAssertTrue(linkUpserts.contains { $0["astridTaskId"] as? String == task.id
            && $0["remoteId"] as? String == "\(repo)#20" })
    }

    /// A page-capped listing cannot prove there is no twin, so nothing is created on GitHub.
    func testATruncatedListingCreatesNoIssue_AITD535() async throws {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        _ = serverTask(in: list.id, title: name("Unsure"))
        fullTruncated = true

        await runPass(listId: list.id)

        XCTAssertTrue(issueCreates.isEmpty)
        XCTAssertEqual(service.lastError, "\(repo): 1 task(s) failed to push")
    }

    // MARK: COMMENTS — two-way per linked task

    /// A linked task and the issue it mirrors, both unchanged since the last pass, so only the
    /// comments phase has anything to do.
    private func linkedTask(issue number: Int, commentMap: [CommentSyncPlanner.MapEntry] = [],
                            commentCount: Int? = nil) async throws -> (list: String, task: Task) {
        let list = try await ListService.shared.createList(name: name("Mirror"))
        let title = name("Discussed")
        let task = try await tasks.createTask(listIds: [list.id], title: title)
        taskLinks = [link(task: task.id, issue: number, syncedAt: Date().addingTimeInterval(-3600),
                          commentMap: commentMap)]
        pulledItems = [issue(number, title: title, notes: task.description, commentCount: commentCount)]
        fullItems = pulledItems
        return (list.id, task)
    }

    private func localComment(on taskId: String, _ content: String) async throws -> Comment {
        try await CommentService.shared.createComment(taskId: taskId, content: content, type: .MARKDOWN,
                                                      authorId: "user-1")
    }

    private func comments(on taskId: String) -> [String] {
        (CommentService.shared.cachedComments[taskId] ?? []).map(\.content)
    }

    func testANewGitHubCommentIsPulledIntoTheTaskWithItsAuthor_AITD535() async throws {
        let (list, task) = try await linkedTask(issue: 30, commentCount: 1)
        remoteComments = [remoteComment("gh-1", body: "Looks good to me", author: "alice")]

        await runPass(listId: list)

        XCTAssertNil(service.lastError)
        XCTAssertEqual(comments(on: task.id),
                       [CommentSyncPlanner.pulledContent(author: "alice", body: "Looks good to me")])
        // Offline the pulled comment keeps its temp id, and a mapping to a temp id would push the
        // comment back to GitHub once the id resolved — so none is written until it is real.
        XCTAssertNil(writtenCommentMap(for: task.id), "no mapping is recorded against a temp id")
        XCTAssertTrue(commentRequests("POST").isEmpty, "a pulled comment is never echoed back")
        XCTAssertEqual(cursorCommits, ["cursor-2"])
    }

    /// A failed fetch of the issue's comments must abort the phase, not read as "no comments" —
    /// that is what once deleted every mirror on the issue — and the pass is not acknowledged.
    func testAFailedCommentFetchChangesNothingAndLeavesTheCursorUncommitted_AITD535() async throws {
        let mirror = CommentSyncPlanner.pulledContent(author: "alice", body: "Keep me")
        let (list, task) = try await linkedTask(issue: 31, commentCount: 1)
        let local = try await localComment(on: task.id, mirror)
        taskLinks = [link(task: task.id, issue: 31, syncedAt: Date().addingTimeInterval(-3600),
                          commentMap: [.init(remoteId: "gh-1", localId: local.id, pushed: false)])]
        commentsStatus = 500

        await runPass(listId: list)

        XCTAssertEqual(service.lastError?.hasPrefix("Comment sync failed"), true)
        XCTAssertEqual(comments(on: task.id), [mirror], "the mirror survives a failed fetch")
        XCTAssertTrue(commentRequests("DELETE").isEmpty)
        XCTAssertEqual(cursorCommits, [])
    }

    func testAGitHubCommentDeletedOnGitHubRemovesItsMirrorAndDropsTheMapping_AITD535() async throws {
        let (list, task) = try await linkedTask(issue: 32)
        let local = try await localComment(on: task.id, CommentSyncPlanner.pulledContent(author: "alice", body: "Gone"))
        taskLinks = [link(task: task.id, issue: 32, syncedAt: Date().addingTimeInterval(-3600),
                          commentMap: [.init(remoteId: "gh-1", localId: local.id, pushed: false)])]
        remoteComments = []

        await runPass(listId: list)

        XCTAssertNil(service.lastError)
        XCTAssertEqual(comments(on: task.id), [], "GitHub is canonical for a pulled comment")
        XCTAssertEqual(writtenCommentMap(for: task.id), "", "the dead entry is dropped from the map")
        XCTAssertEqual(cursorCommits, ["cursor-2"])
    }

    func testAnAstridCommentDeletedInAstridIsDeletedOnGitHub_AITD535() async throws {
        let (list, task) = try await linkedTask(
            issue: 33, commentMap: [.init(remoteId: "gh-7", localId: "comment-deleted-here", pushed: true)])
        remoteComments = [remoteComment("gh-7", body: "Written in Astrid")]

        await runPass(listId: list)

        XCTAssertNil(service.lastError)
        XCTAssertEqual(commentRequests("DELETE").map { $0.query["commentId"] }, ["gh-7"])
        XCTAssertEqual(writtenCommentMap(for: task.id), "")
        XCTAssertEqual(comments(on: task.id), [], "nothing is pulled back in its place")
    }

    func testAGitHubCommentEditedOnGitHubRewritesItsMirror_AITD535() async throws {
        let (list, task) = try await linkedTask(issue: 34)
        let local = try await localComment(on: task.id, CommentSyncPlanner.pulledContent(author: "alice", body: "v1"))
        taskLinks = [link(task: task.id, issue: 34, syncedAt: Date().addingTimeInterval(-3600),
                          commentMap: [.init(remoteId: "gh-1", localId: local.id, pushed: false)])]
        remoteComments = [remoteComment("gh-1", body: "v2", author: "alice")]

        await runPass(listId: list)

        XCTAssertNil(service.lastError)
        XCTAssertEqual(comments(on: task.id), [CommentSyncPlanner.pulledContent(author: "alice", body: "v2")])
        XCTAssertTrue(commentRequests("PATCH").isEmpty, "the mirror converges, GitHub is not rewritten")
        XCTAssertNil(writtenCommentMap(for: task.id), "the map is unchanged, so it is not rewritten")
    }

    func testAnAstridCommentEditedInAstridIsRewrittenOnGitHub_AITD535() async throws {
        let (list, task) = try await linkedTask(issue: 35)
        let local = try await localComment(on: task.id, "Edited in Astrid")
        taskLinks = [link(task: task.id, issue: 35, syncedAt: Date().addingTimeInterval(-3600),
                          commentMap: [.init(remoteId: "gh-9", localId: local.id, pushed: true)])]
        remoteComments = [remoteComment("gh-9", body: "Before the edit")]

        await runPass(listId: list)

        XCTAssertNil(service.lastError)
        let patch = try XCTUnwrap(commentRequests("PATCH").first)
        XCTAssertEqual(patch.jsonBody?["commentId"] as? String, "gh-9")
        XCTAssertEqual(patch.jsonBody?["body"] as? String, "Edited in Astrid")
        XCTAssertEqual(comments(on: task.id), ["Edited in Astrid"], "Astrid is canonical for its own comment")
    }
}
