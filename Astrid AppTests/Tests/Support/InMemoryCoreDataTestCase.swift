import XCTest
import CoreData
@testable import Astrid_App

/// A test case with an in-memory `NSPersistentContainer` loaded from the app's REAL Core Data
/// model (the test bundle does not ship the `.momd`, so it is found through a model class's
/// bundle). If the model XML is malformed or an attribute no longer matches its `@NSManaged`
/// property, container setup fails here, before any round-trip test runs.
class InMemoryCoreDataTestCase: XCTestCase {
    private(set) var container: NSPersistentContainer!
    var context: NSManagedObjectContext { container.viewContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
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

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }
}
