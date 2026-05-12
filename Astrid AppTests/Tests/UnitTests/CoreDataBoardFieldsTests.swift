import XCTest
import CoreData
@testable import Astrid_App

/// Round-trip tests for the new board-related Core Data attributes:
/// project-related fields on CDTaskList + the new CDProject entity.
///
/// Uses an in-memory NSPersistentContainer pointed at the production
/// model. If the model XML is malformed or the new attributes don't match
/// the @NSManaged properties on the classes, container setup fails here.
final class CoreDataBoardFieldsTests: XCTestCase {

    private var container: NSPersistentContainer!

    override func setUpWithError() throws {
        // Load the app's compiled Core Data model from the app bundle —
        // the test bundle doesn't ship the .momd, so we walk to the
        // CDTaskList class's bundle.
        let appBundle = Bundle(for: CDTaskList.self)
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

    // MARK: - CDTaskList board fields

    func testCDTaskList_persistsAllBoardFields() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l-ready"
        cdList.name = "Ready"
        cdList.privacy = "SHARED"
        cdList.ownerId = "u1"
        cdList.syncStatus = "synced"
        cdList.projectId = "p1"
        cdList.listType = "status"
        cdList.statusRole = "ready"
        cdList.statusOrder = NSNumber(value: 0)
        cdList.statusDescription = "Time to get to work!"
        cdList.statusCompleted = NSNumber(value: false)

        try context.save()

        let fetched = try XCTUnwrap(CDTaskList.fetchById("l-ready", context: context))
        XCTAssertEqual(fetched.projectId, "p1")
        XCTAssertEqual(fetched.listType, "status")
        XCTAssertEqual(fetched.statusRole, "ready")
        XCTAssertEqual(fetched.statusOrder?.intValue, 0)
        XCTAssertEqual(fetched.statusDescription, "Time to get to work!")
        XCTAssertEqual(fetched.statusCompleted?.boolValue, false)
    }

    func testCDTaskList_toDomainModel_includesBoardFields() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l-1"
        cdList.name = "Doing"
        cdList.privacy = "SHARED"
        cdList.ownerId = "u1"
        cdList.syncStatus = "synced"
        cdList.projectId = "p1"
        cdList.listType = "status"
        cdList.statusRole = "doing"
        cdList.statusOrder = NSNumber(value: 1)

        let domain = cdList.toDomainModel()
        XCTAssertEqual(domain.projectId, "p1")
        XCTAssertEqual(domain.listType, "status")
        XCTAssertEqual(domain.statusRole, "doing")
        XCTAssertEqual(domain.statusOrder, 1)
    }

    func testCDTaskList_updateFromDomain_persistsRecentlyCompletedWindow() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l-1"
        cdList.name = "Test"
        cdList.privacy = "PRIVATE"
        cdList.ownerId = "u1"
        cdList.syncStatus = "synced"

        var domain = TaskList(id: "l-1", name: "Test")
        domain.ownerId = "u1"
        domain.privacy = .PRIVATE
        domain.recentlyCompletedWindow = .duration(amount: 7, unit: .day)

        cdList.update(from: domain)
        try context.save()

        let fetched = try XCTUnwrap(CDTaskList.fetchById("l-1", context: context))
        XCTAssertNotNil(fetched.recentlyCompletedWindowJSON)

        let roundTrip = fetched.toDomainModel()
        XCTAssertEqual(roundTrip.recentlyCompletedWindow, .duration(amount: 7, unit: .day))
    }

    func testCDTaskList_nilRecentlyCompletedWindow_persistsAsNull() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l-legacy"
        cdList.name = "Legacy"
        cdList.privacy = "PRIVATE"
        cdList.ownerId = "u1"
        cdList.syncStatus = "synced"

        var domain = TaskList(id: "l-legacy", name: "Legacy")
        domain.ownerId = "u1"
        domain.privacy = .PRIVATE
        // recentlyCompletedWindow stays nil
        cdList.update(from: domain)
        try context.save()

        let fetched = try XCTUnwrap(CDTaskList.fetchById("l-legacy", context: context))
        XCTAssertNil(fetched.recentlyCompletedWindowJSON)
        XCTAssertNil(fetched.toDomainModel().recentlyCompletedWindow)
    }

    // MARK: - CDProject

    func testCDProject_persistsAndRoundTrips() throws {
        let cdProject = CDProject(context: context)
        cdProject.id = "p1"
        cdProject.name = "Astrid Dev"
        cdProject.projectDescription = "Internal board"
        cdProject.color = "#3b82f6"
        cdProject.ownerId = "u1"
        cdProject.syncStatus = "synced"
        cdProject.createdAt = Date()
        cdProject.updatedAt = Date()

        try context.save()

        let fetched = try XCTUnwrap(CDProject.fetchById("p1", context: context))
        XCTAssertEqual(fetched.name, "Astrid Dev")
        XCTAssertEqual(fetched.ownerId, "u1")
        XCTAssertEqual(fetched.projectDescription, "Internal board")

        let domain = fetched.toDomainModel()
        XCTAssertEqual(domain.id, "p1")
        XCTAssertEqual(domain.name, "Astrid Dev")
        XCTAssertEqual(domain.description, "Internal board")
    }

    func testCDProject_updateFromDomain() throws {
        let cdProject = CDProject(context: context)
        cdProject.id = "p1"
        cdProject.name = "Old Name"
        cdProject.ownerId = "u1"
        cdProject.syncStatus = "synced"

        let domain = Project(
            id: "p1",
            name: "New Name",
            description: "Updated",
            color: "#ff0000",
            ownerId: "u1"
        )
        cdProject.update(from: domain)
        try context.save()

        let fetched = try XCTUnwrap(CDProject.fetchById("p1", context: context))
        XCTAssertEqual(fetched.name, "New Name")
        XCTAssertEqual(fetched.projectDescription, "Updated")
        XCTAssertEqual(fetched.color, "#ff0000")
    }

    func testCDProject_fetchAll_returnsCreatedProjects() throws {
        for i in 0..<3 {
            let cd = CDProject(context: context)
            cd.id = "p\(i)"
            cd.name = "Project \(i)"
            cd.ownerId = "u1"
            cd.syncStatus = "synced"
            cd.createdAt = Date().addingTimeInterval(TimeInterval(i))
        }
        try context.save()

        let all = try CDProject.fetchAll(context: context)
        XCTAssertEqual(all.count, 3)
        // Sorted by createdAt descending
        XCTAssertEqual(all.first?.id, "p2")
    }
}
