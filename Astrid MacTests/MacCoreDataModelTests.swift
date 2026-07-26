//  MacCoreDataModelTests.swift
//  Regression for task f14559e8 — the Mac app shipped WITHOUT the shared CoreData model.
//
//  `AstridApp.xcdatamodeld` was compiled into the iOS target only; the Mac target carried the
//  Xcode template stub (`Astrid_Mac.xcdatamodeld`, one `Item` entity). CoreDataManager loads
//  `NSPersistentContainer(name: "AstridApp")`, so on macOS every launch logged
//  "Failed to load model named AstridApp" and the app ran with NO local persistence — nothing
//  survived a relaunch and every CoreData-backed read came back empty.
//
//  Asserts the BUILT host bundle (never the repo tree — a sandboxed test host touching
//  ~/Documents hangs on TCC, see MacAppIconTests).

import XCTest
import CoreData
@testable import Astrid_Mac

final class MacCoreDataModelTests: XCTestCase {

    /// The model CoreDataManager asks for by name must exist in the Mac app bundle.
    func testSharedModelIsBundledWithTheMacApp() throws {
        let url = Bundle.main.url(forResource: "AstridApp", withExtension: "momd")
        XCTAssertNotNil(url, "AstridApp.momd is missing from the Mac bundle — CoreData cannot load")
    }

    /// It must be the REAL shared model, not the template stub.
    func testBundledModelContainsTheAppsEntities() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AstridApp", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        let names = Set(model.entities.compactMap(\.name))

        XCTAssertTrue(names.contains("CDTask"),
                      "Bundled model lacks CDTask — got \(names.sorted())")
        XCTAssertFalse(names == ["Item"],
                       "Bundled model is the Xcode template stub, not the app's model")
    }

    /// The container the app actually builds must load a store with those entities.
    func testPersistentContainerLoadsTheSharedModel() throws {
        let container = NSPersistentContainer(name: "AstridApp")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType          // never touch the user's real store
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Persistent store failed to load: \(String(describing: loadError))")
        XCTAssertTrue(container.managedObjectModel.entities.contains { $0.name == "CDTask" })
    }
}
