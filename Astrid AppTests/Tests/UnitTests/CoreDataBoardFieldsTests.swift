import XCTest
import CoreData
@testable import Astrid_App

/// The read side of the board-related Core Data attributes — what the one-time `CoreUpgrade`
/// seed reads back: project fields on CDTaskList and the CDProject entity. (The write side,
/// `update(from:)`, went with the Swift data layer.)
///
/// Uses the in-memory container from `InMemoryCoreDataTestCase`, pointed at the production model.
final class CoreDataBoardFieldsTests: InMemoryCoreDataTestCase {

    // MARK: - CDTaskList board fields

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

    // MARK: - CDProject

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
