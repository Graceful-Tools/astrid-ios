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

    // MARK: - Icon column

    /// The icon sits centred in a column as wide as the logo, starting where the logo starts, and
    /// the name follows after the header's own gap — so the names line up with the wordmark.
    func test_aitd502_listIconsSitInTheLogoColumn() throws {
        for (name, source) in [("list row", try rowSource()), ("My Tasks row", try myTasksRowSource())] {
            XCTAssertTrue(source.contains(".frame(width: SidebarBrandHeader.logoSize)"),
                          "the \(name)'s icon is not in the logo's column")
            XCTAssertTrue(source.contains("HStack(spacing: SidebarBrandHeader.spacing)"),
                          "the \(name)'s name does not follow the icon by the header's gap")
            XCTAssertFalse(source.contains(".padding(.horizontal, Theme.spacing12)"),
                           "the \(name) still pads its leading edge, which pushes the icon right of the logo")
        }
    }

    // MARK: - Count

    func test_aitd502_theCountIsNearlyTheSizeOfTheName() throws {
        for (name, source) in [("list row", try rowSource()), ("My Tasks row", try myTasksRowSource())] {
            XCTAssertTrue(source.contains("Theme.Typography.callout()"), "the \(name)'s count is not callout-sized")
            XCTAssertFalse(source.contains("Theme.Typography.caption1()"), "the \(name)'s count is still caption-sized")
        }
    }

    func test_aitd502_theCountSitsCloserToTheRightEdge() throws {
        for (name, source) in [("list row", try rowSource()), ("My Tasks row", try myTasksRowSource())] {
            XCTAssertTrue(source.contains(".padding(.trailing, Theme.spacing4)"),
                          "the \(name)'s count keeps the old trailing inset")
        }
    }
}
