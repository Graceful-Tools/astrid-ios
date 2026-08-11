//  CoreDataShowSubtasksTests.swift
//  Regression guard for Task ba1deb9d — the STORAGE half of per-list show/hide subtasks.
//
//  The task names the failure mode it is worried about: 2e41c645, where a field was decoded from
//  the wire and then never written to Core Data, so it survived exactly until the next relaunch.
//  These round-trip the attribute through the real model.
//
//  The distinction that has to survive is three-valued, not two: absent (no opinion → SHOW),
//  true, and false. A scalar Bool attribute would collapse absent into false and hide subtasks in
//  every list decoded by a build that predates the field.

import XCTest
import CoreData
@testable import Astrid_App

final class CoreDataShowSubtasksTests: XCTestCase {

    private var container: NSPersistentContainer!

    override func setUpWithError() throws {
        let appBundle = Bundle(for: CDTaskList.self)
        let modelURL = try XCTUnwrap(appBundle.url(forResource: "AstridApp", withExtension: "momd"),
                                     "Could not find AstridApp.momd in the app bundle")
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

    private func list(id: String, showSubtasks: Bool?) -> TaskList {
        var l = TaskList(id: id, name: "L", privacy: .PRIVATE)
        l.showSubtasks = showSubtasks
        return l
    }

    /// A list saved with subtasks OFF must still be off after a relaunch reads it back.
    func testHiddenSubtasksSurviveARelaunch() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l1"
        cdList.update(from: list(id: "l1", showSubtasks: false))
        cdList.syncStatus = "synced"
        try context.save()

        let fetched = try XCTUnwrap(CDTaskList.fetchById("l1", context: context))
        XCTAssertEqual(fetched.toDomainModel().showSubtasks, false,
                       "Decoding without storing is the 2e41c645 bug; this must round-trip")
    }

    func testShownSubtasksRoundTrip() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l2"
        cdList.update(from: list(id: "l2", showSubtasks: true))
        cdList.syncStatus = "synced"
        try context.save()

        XCTAssertEqual(try XCTUnwrap(CDTaskList.fetchById("l2", context: context))
            .toDomainModel().showSubtasks, true)
    }

    /// The three-valued case: "no opinion" must come back as nil, NOT as false. A scalar Bool
    /// attribute would fail here, and every pre-existing list would lose its subtasks.
    func testNoOpinionStaysNilRatherThanBecomingFalse() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l3"
        cdList.update(from: list(id: "l3", showSubtasks: nil))
        cdList.syncStatus = "synced"
        try context.save()

        let domain = try XCTUnwrap(CDTaskList.fetchById("l3", context: context)).toDomainModel()
        XCTAssertNil(domain.showSubtasks)
        XCTAssertTrue(ListSubtaskVisibility.listShowsSubtasks(domain.showSubtasks),
                      "Absent means SHOW")
    }

    /// Turning it back on has to overwrite a stored false, not merely fail to clear it.
    func testTogglingBackOnOverwritesTheStoredValue() throws {
        let cdList = CDTaskList(context: context)
        cdList.id = "l4"
        cdList.update(from: list(id: "l4", showSubtasks: false))
        cdList.syncStatus = "synced"
        try context.save()

        cdList.update(from: list(id: "l4", showSubtasks: true))
        try context.save()

        XCTAssertEqual(try XCTUnwrap(CDTaskList.fetchById("l4", context: context))
            .toDomainModel().showSubtasks, true)
    }
}
