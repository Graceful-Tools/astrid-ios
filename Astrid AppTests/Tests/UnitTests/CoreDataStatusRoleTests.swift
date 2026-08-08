import XCTest
import CoreData
@testable import Astrid_App

/// `Task.statusRole` has to survive Core Data (task 2e41c645).
///
/// The board prefers the field over list membership when picking a column, and
/// `Task` decodes it from the API — but `CDTask` never stored it. The role was
/// dropped on every local persist and read back nil, so it survived a fresh
/// fetch and died on relaunch.
///
/// The membership fallback in `getTaskProjectColumnId` hides this today. It
/// stops hiding it the moment web stops dual-writing memberships: the field is
/// nil from cache, the membership is gone, and every card falls to Inbox. That
/// makes this a prerequisite for retiring the status lists, not a cosmetic fix.
final class CoreDataStatusRoleTests: XCTestCase {

    private var container: NSPersistentContainer!

    override func setUpWithError() throws {
        let appBundle = Bundle(for: CDTask.self)
        let modelURL = try XCTUnwrap(
            appBundle.url(forResource: "AstridApp", withExtension: "momd"),
            "Could not find AstridApp.momd in the app bundle"
        )
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        container = NSPersistentContainer(name: "AstridApp", managedObjectModel: model)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldMigrateStoreAutomatically = true
        store.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [store]

        let exp = expectation(description: "container loaded")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error, "Container failed to load: \(error?.localizedDescription ?? "?")")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
    }

    private var context: NSManagedObjectContext { container.viewContext }

    private func makeTask(id: String, statusRole: String?) -> Task {
        Task(
            id: id,
            title: "Card",
            description: "",
            creatorId: "u1",
            statusRole: statusRole
        )
    }

    /// `update(from:)` sets neither `id` nor `syncStatus`; the entity requires both.
    @discardableResult
    private func insert(_ task: Task) -> CDTask {
        let cdTask = CDTask(context: context)
        cdTask.id = task.id
        cdTask.syncStatus = "synced"
        cdTask.update(from: task)
        return cdTask
    }

    // MARK: - Round trip

    func testStatusRole_survivesSaveAndFetch() throws {
        insert(makeTask(id: "t-doing", statusRole: "doing"))
        try context.save()

        let fetched = try XCTUnwrap(CDTask.fetchById("t-doing", context: context))

        XCTAssertEqual(fetched.statusRole, "doing")
        XCTAssertEqual(fetched.toDomainModel().statusRole, "doing")
    }

    func testStatusRole_roundTripsACustomState() throws {
        // Custom roles have no backing default; the column matches on the raw
        // string, so it has to survive verbatim.
        insert(makeTask(id: "t-custom", statusRole: "custom-blocked"))
        try context.save()

        let fetched = try XCTUnwrap(CDTask.fetchById("t-custom", context: context))

        XCTAssertEqual(fetched.toDomainModel().statusRole, "custom-blocked")
    }

    // MARK: - Clearing

    func testStatusRole_nilMeansInbox_andPersistsAsNil() throws {
        insert(makeTask(id: "t-inbox", statusRole: nil))
        try context.save()

        let fetched = try XCTUnwrap(CDTask.fetchById("t-inbox", context: context))

        XCTAssertNil(fetched.statusRole)
        XCTAssertNil(fetched.toDomainModel().statusRole)
    }

    func testStatusRole_movingToInboxClearsTheStoredRole() throws {
        // The bug this guards: an update that clears the role must overwrite the
        // stored value, not leave the previous one behind. A stale role reads
        // back as the OLD column, which is exactly the "moving out of Ready
        // doesn't stick" failure the field was meant to end.
        let cdTask = insert(makeTask(id: "t-move", statusRole: "ready"))
        try context.save()

        cdTask.update(from: makeTask(id: "t-move", statusRole: nil))
        try context.save()

        let fetched = try XCTUnwrap(CDTask.fetchById("t-move", context: context))
        XCTAssertNil(fetched.toDomainModel().statusRole)
    }

    // MARK: - What the board does with the restored value

    func testCachedTaskResolvesItsColumnWithoutAnyMembership() throws {
        // The end state this is all for: once the status lists are gone, a task
        // loaded from cache carries no status membership at all, and the role
        // alone has to place the card.
        var ready = TaskList(id: "l-ready", name: "Ready")
        ready.listType = "status"
        ready.statusRole = "ready"
        ready.statusOrder = 0

        insert(makeTask(id: "t-cached", statusRole: "ready"))
        try context.save()

        let restored = try XCTUnwrap(CDTask.fetchById("t-cached", context: context)).toDomainModel()

        XCTAssertTrue(restored.listIds?.isEmpty ?? true, "no membership — the role is the only signal")
        XCTAssertEqual(getTaskProjectColumnId(restored, lists: [ready]), "l-ready")
    }
}
