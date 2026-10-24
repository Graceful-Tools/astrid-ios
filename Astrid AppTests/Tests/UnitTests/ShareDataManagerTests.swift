//  ShareDataManagerTests.swift
//  The App Group hand-off between the Share Extension and the app (AITD-542). Until this, the only
//  tests here were plist and entitlement guards; nothing exercised a share going in one side and
//  coming out the other.

import XCTest
@testable import Astrid_App

final class ShareDataManagerTests: XCTestCase {
    private var container: URL!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareDataManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    private var pendingFile: URL { container.appendingPathComponent("pending_tasks.json") }

    func testAShareRoundTripsThroughTheContainerAndClearsOnceConsumed_AITD542() throws {
        let manager = ShareDataManager(containerURL: container)
        let shared = SharedTaskData(title: "Read this", description: "https://example.com", priority: 2)
        try manager.saveSharedTask(shared)

        // A second manager over the same container is the app reading what the extension wrote.
        let app = ShareDataManager(containerURL: container)
        let pending = try app.loadPendingTasks()
        XCTAssertEqual(pending.map(\.data.id), [shared.id])
        XCTAssertEqual(pending.first?.data.title, "Read this")
        XCTAssertEqual(pending.first?.data.description, "https://example.com")
        XCTAssertEqual(pending.first?.data.priority, 2)
        XCTAssertEqual(pending.first?.status, .pending)

        try app.updateTaskStatus(taskId: shared.id, status: .completed, createdTaskId: "task-1")
        XCTAssertEqual(try app.loadPendingTasks().first?.taskId, "task-1")
        try app.removeCompletedTasks()
        XCTAssertEqual(try app.loadPendingTasks().count, 0, "a consumed share leaves the queue")
    }

    func testAFailureKeepsItsReasonAndStaysQueued_AITD542() throws {
        let manager = ShareDataManager(containerURL: container)
        let shared = SharedTaskData(title: "Will fail")
        try manager.saveSharedTask(shared)
        try manager.updateTaskStatus(taskId: shared.id, status: .failed, error: "offline")
        try manager.updateTaskStatus(taskId: "no-such-share", status: .completed)
        try manager.removeCompletedTasks()

        let pending = try manager.loadPendingTasks()
        XCTAssertEqual(pending.map(\.status), [.failed])
        XCTAssertEqual(pending.first?.errorMessage, "offline")
    }

    /// One unreadable file used to make `loadPendingTasks` throw — and `saveSharedTask` loads
    /// first, so every share after it failed too, for good.
    func testACorruptQueueIsDroppedAndTheNextShareStillSaves_AITD542() throws {
        try Data("{not json".utf8).write(to: pendingFile)
        let manager = ShareDataManager(containerURL: container)

        XCTAssertEqual(try manager.loadPendingTasks().count, 0, "a corrupt queue reads as empty, not as an error")
        let next = SharedTaskData(title: "After the corruption")
        XCTAssertNoThrow(try manager.saveSharedTask(next))
        XCTAssertEqual(try manager.loadPendingTasks().map(\.data.id), [next.id])
    }

    /// An entry this build cannot read (an older or newer shape) costs that entry, not its neighbours.
    func testAnUnreadableEntryIsDroppedAndTheRestKept_AITD542() throws {
        let manager = ShareDataManager(containerURL: container)
        let good = SharedTaskData(title: "Readable")
        try manager.saveSharedTask(good)

        var entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pendingFile)) as? [Any])
        entries.insert(["data": ["title": "no id or date"], "status": "pending"], at: 0)
        try JSONSerialization.data(withJSONObject: entries).write(to: pendingFile)

        XCTAssertEqual(try manager.loadPendingTasks().map(\.data.id), [good.id])
    }

    /// A wrong App Group id resolves to no container. The share must fail loudly — the extension
    /// shows the error — rather than vanish.
    func testWithoutAContainerEverySaveAndReadThrows_AITD542() {
        let manager = ShareDataManager(containerURL: nil)
        XCTAssertFalse(manager.validateAppGroupAccess())
        XCTAssertThrowsError(try manager.saveSharedTask(SharedTaskData(title: "Lost?"))) { error in
            XCTAssertEqual(error as? ShareDataError, .appGroupNotConfigured)
        }
        XCTAssertThrowsError(try manager.loadPendingTasks())
        XCTAssertThrowsError(try manager.copyFileToSharedContainer(from: container))
        XCTAssertNotNil(ShareDataError.appGroupNotConfigured.errorDescription)
    }

    func testFilesCopyIntoTheContainerAndOldOnesAreCleanedUp_AITD542() throws {
        let manager = ShareDataManager(containerURL: container)
        let source = container.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3]).write(to: source)

        let copied = try manager.copyFileToSharedContainer(from: source)
        XCTAssertEqual(copied.deletingLastPathComponent().lastPathComponent, "shared_files")
        XCTAssertEqual(copied.pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: copied), Data([1, 2, 3]))

        let stale = try manager.copyFileToSharedContainer(from: source)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: -8 * 86_400)],
                                              ofItemAtPath: stale.path)
        try manager.cleanupOldFiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path), "a fresh file stays")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "a week-old file goes")

        try manager.deleteSharedFile(at: copied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
    }
}
