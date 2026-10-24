import XCTest
@testable import Astrid_App

/// Search, inline at the far right of the sidebar's brand header (AITD-494, AWTD-1180).
///
/// Jon: *"(a) but add search icon inline on far right. Logo left header with Astrid / brand
/// logo on top left. Do across interfaces."* (a) is the sidebar's Search ROW, which stays: the
/// icon is a second way in, so the two must not be able to lead to different places.
final class SidebarSearchEntryTests: XCTestCase {

    func test_aitd494_theHeaderIconLeadsToSearch() {
        XCTAssertEqual(SidebarSearchEntry.headerIcon.destination, .search)
    }

    func test_aitd494_everySearchEntryLeadsToTheSamePlace() {
        let destinations = SidebarSearchEntry.allCases.map(\.destination)
        XCTAssertEqual(destinations, Array(repeating: .search, count: destinations.count))
    }
}
