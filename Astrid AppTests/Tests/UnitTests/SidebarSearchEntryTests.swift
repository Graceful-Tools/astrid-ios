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

    /// Pinned at the source, as web's `sidebar-header-search.test.ts` is: a render of either
    /// sidebar needs the services, the session and the list store to say what the markup does.
    /// iOS dropped its Search row in AITD-497 (`SidebarAccountFooterTests`); the Mac keeps both.
    func test_aitd494_bothSidebarsOpenSearchFromTheHeader() throws {
        let ios = try RepositoryLocator.source(at: "Astrid App/Views/Lists/ListSidebarView.swift")
        XCTAssertTrue(ios.contains("openSearch(.headerIcon)"), "iOS: the header icon is gone")
        XCTAssertEqual(ios.components(separatedBy: "selectedListId = \"search\"").count - 1, 1,
                       "iOS: search is opened in exactly one place")

        let mac = try RepositoryLocator.source(at: "Astrid Mac/App/MacRootView.swift")
        XCTAssertTrue(mac.contains("MacSidebarHeader("), "Mac: the brand header is gone")
        XCTAssertTrue(mac.contains("\"sidebar.search\""), "Mac: the Search row stays")
    }

    func test_aitd494_theHeaderPutsTheLogoLeftAndSearchRight() throws {
        let header = try RepositoryLocator.source(at: "Astrid App/Core/Layout/SidebarBrandHeader.swift")
        // The brand's character, resolved through Brand since AITD-514.
        let logo = try XCTUnwrap(header.range(of: "Brand.characterImage"))
        let search = try XCTUnwrap(header.range(of: "\"magnifyingglass\""))
        XCTAssertLessThan(logo.lowerBound, search.lowerBound)
        // Labelled for a screen reader rather than shipped as a bare icon.
        XCTAssertTrue(header.contains(".accessibilityLabel(NSLocalizedString(\"actions.search\""))
    }
}
