//  SharedTaskInboxTests.swift
//  The app's half of a share (AITD-542): what the extension queued in the App Group becomes a task
//  through TaskService — a create in the core's journal — and leaves the queue.

import XCTest
import AstridCore
@testable import Astrid_App

@MainActor
final class SharedTaskInboxTests: XCTestCase {
    private struct Stats: Decodable { let pending: Int; let running: Int }

    private var container: URL!
    private var shares: ShareDataManager!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedTaskInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        shares = ShareDataManager(containerURL: container)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    func testAQueuedShareBecomesAJournaledCreateAndLeavesTheQueue_AITD542() async throws {
        let core = try CoreSearchFixture.session(seeding: [])
        let service = TaskService(core: core)
        let title = "Shared \(UUID().uuidString)"
        try shares.saveSharedTask(SharedTaskData(title: title, description: "https://example.com", priority: 1))

        let inbox = SharedTaskInbox(shares: shares, tasks: service, assigneeId: { nil },
                                    upload: { _, _, _, _ in XCTFail("no file, no upload") })
        let created = await inbox.drain()

        XCTAssertEqual(created, 1)
        let task = try XCTUnwrap(service.tasks.first { $0.title == title }, "the share is a task")
        XCTAssertEqual(task.description, "https://example.com")
        XCTAssertEqual(task.priority.rawValue, 1)
        let stats = try await core.run(CoreCommand(kind: "outboxStats"), as: Stats.self)
        XCTAssertGreaterThan(stats.pending + stats.running, 0, "the create is journaled for the server")
        XCTAssertEqual(try shares.loadPendingTasks().count, 0, "a consumed share leaves the queue")
    }

    func testAnAttachedFileIsUploadedToTheNewTask_AITD542() async throws {
        let service = TaskService(core: try CoreSearchFixture.session(seeding: []))
        let fileURL = container.appendingPathComponent("shared_files/a.jpg")
        try shares.saveSharedTask(SharedTaskData(title: "With a photo", fileURL: fileURL,
                                                 fileName: "a.jpg", mimeType: "image/jpeg", fileSize: 4))
        var uploads: [(URL, String, String, String)] = []
        let inbox = SharedTaskInbox(shares: shares, tasks: service, assigneeId: { nil },
                                    upload: { uploads.append(($0, $1, $2, $3)) })

        await inbox.drain()

        let task = try XCTUnwrap(service.tasks.first { $0.title == "With a photo" })
        XCTAssertEqual(uploads.count, 1)
        XCTAssertEqual(uploads.first?.0, fileURL)
        XCTAssertEqual(uploads.first?.1, "a.jpg")
        XCTAssertEqual(uploads.first?.2, "image/jpeg")
        XCTAssertEqual(uploads.first?.3, task.id, "the file goes to the task the share became")
        XCTAssertEqual(try shares.loadPendingTasks().count, 0)
    }

    /// A share whose upload fails stays queued, failed with its reason — not silently dropped,
    /// and not re-created as a second task on the next launch.
    func testAFailedShareStaysQueuedAndIsNotCreatedTwice_AITD542() async throws {
        struct Offline: LocalizedError { var errorDescription: String? { "offline" } }
        let service = TaskService(core: try CoreSearchFixture.session(seeding: []))
        try shares.saveSharedTask(SharedTaskData(title: "Upload fails", fileURL: container,
                                                 fileName: "a.jpg", mimeType: "image/jpeg"))
        let inbox = SharedTaskInbox(shares: shares, tasks: service, assigneeId: { nil },
                                    upload: { _, _, _, _ in throw Offline() })

        let first = await inbox.drain()
        let second = await inbox.drain()

        XCTAssertEqual(first + second, 0)
        let queued = try shares.loadPendingTasks()
        XCTAssertEqual(queued.map(\.status), [.failed])
        XCTAssertEqual(queued.first?.errorMessage, "offline")
        XCTAssertEqual(service.tasks.filter { $0.title == "Upload fails" }.count, 1)
    }

    func testAnEmptyOrUnreachableQueueIsANoOp_AITD542() async throws {
        let service = TaskService(core: try CoreSearchFixture.session(seeding: []))
        let empty = await SharedTaskInbox(shares: shares, tasks: service).drain()
        XCTAssertEqual(empty, 0)
        let unreachable = await SharedTaskInbox(shares: ShareDataManager(containerURL: nil), tasks: service).drain()
        XCTAssertEqual(unreachable, 0)
    }
}
