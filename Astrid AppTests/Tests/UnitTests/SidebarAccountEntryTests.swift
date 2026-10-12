import XCTest
@testable import Astrid_App

/// The sidebar's user card leads to Settings, as web's user menu does (AITD-493, AWTD-1179).
///
/// It opened the Profile screen while the gear beside it opened Settings: two controls in one
/// row, two destinations, and neither of them where web's single user menu goes.
final class SidebarAccountEntryTests: XCTestCase {

    func test_aitd493_theUserCardLeadsToSettings() {
        XCTAssertEqual(SidebarAccountEntry.userCard.destination, .settings)
    }

    func test_aitd493_everyAccountControlLeadsToTheSamePlace() {
        let destinations = SidebarAccountEntry.allCases.map(\.destination)
        XCTAssertEqual(destinations, Array(repeating: .settings, count: destinations.count))
    }
}
