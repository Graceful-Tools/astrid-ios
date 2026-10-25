import XCTest
@testable import Astrid_App

/// The iOS sidebar's polish pass (AITD-502).
///
/// Jon, with a screenshot of the sidebar: *"Make the list icons / colors line up with Astrid
/// logo. Keep the current text alignment. Make the list task count number larger nearly same
/// font size as list name. Shift the list number container towards right border a bit. Increase
/// font size of Astrid in the title by 20% and size of Astrid icon."*
///
/// Pinned at the source, as the footer's tests are: a render needs the services and the session.
final class SidebarPolishTests: XCTestCase {

    private func rowSource() throws -> String {
        try RepositoryLocator.source(at: "Astrid App/Views/Lists/ListRowView.swift")
    }

    /// The My Tasks row's own declaration, up to the next section of the sidebar.
    private func myTasksRowSource() throws -> String {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Lists/ListSidebarView.swift")
        let open = try XCTUnwrap(source.range(of: "private var myTasksRow: some View"))
        let close = try XCTUnwrap(source.range(of: "// MARK: - Computed Properties", range: open.upperBound..<source.endIndex))
        return String(source[open.upperBound..<close.lowerBound])
    }

    // MARK: - Header

    func test_aitd502_theWordmarkIsTwentyPercentLarger() {
        XCTAssertEqual(SidebarBrandHeader.wordmarkSize, 18 * 1.2, accuracy: 0.01)
    }

    func test_aitd502_theLogoIsTwentyPercentLarger() {
        XCTAssertEqual(SidebarBrandHeader.logoSize, 24 * 1.2, accuracy: 0.01)
    }
}
