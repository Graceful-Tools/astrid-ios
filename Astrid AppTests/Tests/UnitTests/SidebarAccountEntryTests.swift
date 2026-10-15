import XCTest
@testable import Astrid_App

/// The sidebar's user card opens the profile; the gear beside it opens Settings (AITD-502).
///
/// Jon: *"Make tapping profile and tapping gear separated, where gear take you to settings. User
/// profile to user profile."* Both had led to Settings since AITD-493 matched web's single user
/// menu, which left the footer with two controls and one destination.
final class SidebarAccountEntryTests: XCTestCase {

    func test_aitd502_theUserCardLeadsToTheProfile() {
        XCTAssertEqual(SidebarAccountEntry.userCard.destination, .profile)
    }

    func test_aitd502_theGearLeadsToSettings() {
        XCTAssertEqual(SidebarAccountEntry.gear.destination, .settings)
    }
}
