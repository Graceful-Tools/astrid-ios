import XCTest
@testable import Astrid_App

/// The iOS sidebar: no Search row, and the user card in a footer fixed to the bottom (AITD-497).
///
/// Jon: *"remove search row. move user profile and setting to fixed footer like mobile web."*
/// The sidebar opened with four cards before the first list — brand header, user card, My Tasks,
/// Search — and the Search row repeated the magnifying glass the header already carries.
///
/// Pinned at the source, as the header's tests are: a render of the sidebar needs the services,
/// the session and the list store to say what the markup does.
final class SidebarAccountFooterTests: XCTestCase {

    private func sidebarSource() throws -> String {
        try RepositoryLocator.source(at: "Astrid App/Views/Lists/ListSidebarView.swift")
    }

    /// What scrolls: everything between `List {` and the modifiers that follow it.
    private func scrollingRows() throws -> String {
        let source = try sidebarSource()
        let open = try XCTUnwrap(source.range(of: "List {"))
        let close = try XCTUnwrap(source.range(of: ".listStyle(.sidebar)", range: open.upperBound..<source.endIndex))
        return String(source[open.upperBound..<close.lowerBound])
    }

    func test_aitd497_theSearchRowIsGone() throws {
        let source = try sidebarSource()
        XCTAssertFalse(source.contains("searchRow"), "the Search row is still among the lists")
        XCTAssertFalse(source.contains("openSearch(.row)"), "something still opens search as the row did")
    }

    func test_aitd497_theHeaderIconIsStillTheWayIntoSearch() throws {
        XCTAssertTrue(try sidebarSource().contains("openSearch(.headerIcon)"),
                      "with the row gone, the header icon is the only way into search")
    }

    func test_aitd497_theUserCardDoesNotScrollWithTheLists() throws {
        XCTAssertFalse(try scrollingRows().contains("userProfileSection"),
                       "the user card is still a row of the scrolling list")
    }

    func test_aitd497_theUserCardAndGearAreAFooterFixedToTheBottom() throws {
        let source = try sidebarSource()
        let inset = try XCTUnwrap(source.range(of: ".safeAreaInset(edge: .bottom"),
                                  "nothing is fixed to the bottom of the sidebar")
        let footer = source[inset.upperBound...].prefix(120)
        XCTAssertTrue(footer.contains("accountFooter"), "the bottom inset is not the account footer")
        // Both controls travel together, and still ask SidebarAccountEntry where they lead.
        XCTAssertTrue(source.contains("openAccountEntry(.userCard)"))
        XCTAssertTrue(source.contains("openAccountEntry(.gear)"))
    }

    func test_aitd497_theSidebarOpensWithTheBrandHeaderThenMyTasks() throws {
        let rows = try scrollingRows()
        let header = try XCTUnwrap(rows.range(of: "brandHeaderSection"))
        let myTasks = try XCTUnwrap(rows.range(of: "myTasksSection"))
        let favorites = try XCTUnwrap(rows.range(of: "favoritesSection"))
        XCTAssertLessThan(header.lowerBound, myTasks.lowerBound)
        XCTAssertLessThan(myTasks.lowerBound, favorites.lowerBound)
    }
}

/// The footer is glass, not an opaque band of the theme colour (AITD-501).
///
/// Jon: *"Make the left footer with the profile and setting icon glass."* His screenshot shows a
/// solid cyan block slicing the Health row in half: the lists scroll under the footer, and the
/// theme fill hid them instead of letting them show through.
final class SidebarAccountFooterGlassTests: XCTestCase {

    /// The footer's own declaration, up to the next section of the file.
    private func footerSource() throws -> String {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Lists/ListSidebarView.swift")
        let open = try XCTUnwrap(source.range(of: "private var accountFooter: some View"))
        let close = try XCTUnwrap(source.range(of: "// MARK: - Search", range: open.upperBound..<source.endIndex))
        return String(source[open.upperBound..<close.lowerBound])
    }

    func test_aitd501_theFooterIsGlass() throws {
        XCTAssertTrue(try footerSource().contains(".glassEffect("), "the account footer is not glass")
    }

    func test_aitd501_theFooterIsNotFilledWithTheThemeColour() throws {
        XCTAssertFalse(try footerSource().contains(".background(themeBackgroundColor)"),
                       "an opaque theme fill still hides the lists scrolling under the footer")
    }
}
