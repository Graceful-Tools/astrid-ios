//  MacSelectionStyleTests.swift
//  Astrid for Mac — Task b8d1ec16: selection border must be subtle (thin), not heavy.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacSelectionStyleTests: XCTestCase {

    func testSelectedBorderIsSubtle() {
        let sel = MacSelectionStyle.borderWidth(isSelected: true)
        let unsel = MacSelectionStyle.borderWidth(isSelected: false)
        XCTAssertGreaterThan(sel, unsel, "Selected must be visible vs unselected")
        XCTAssertLessThanOrEqual(sel, 1.5, "Selected border must stay subtle (no heavy 2.5pt)")
        XCTAssertLessThan(sel, 2.5, "Must be subtler than the old iOS 2.5pt border")
        XCTAssertEqual(unsel, 0.5)
    }

    /// Hover affordance (77225941) + white selected card (0f695ef2): the SELECTED card keeps the
    /// plain card surface — only the border carries selection; hover is a faint wash.
    func testHoverTierAndWhiteSelectedCard() {
        let normal = MacSelectionStyle.fill(isSelected: false, hovering: false)
        let hover = MacSelectionStyle.fill(isSelected: false, hovering: true)
        let selected = MacSelectionStyle.fill(isSelected: true, hovering: false)
        XCTAssertNotEqual(hover, normal, "Hover must be visible vs normal")
        XCTAssertEqual(selected, normal, "Selected card stays the plain card surface (no dark-blue row)")
        // Selection is carried by the BORDER, and suppresses the hover wash.
        XCTAssertNotEqual(MacSelectionStyle.borderColor(isSelected: true),
                          MacSelectionStyle.borderColor(isSelected: false))
        XCTAssertEqual(MacSelectionStyle.fill(isSelected: true, hovering: true), selected)
        // Border also distinguishes hover from normal.
        XCTAssertNotEqual(MacSelectionStyle.borderColor(isSelected: false, hovering: true),
                          MacSelectionStyle.borderColor(isSelected: false, hovering: false))
    }
}
#endif

// MARK: - Hover colour parity with the web (reported: "the hover task color is off")

extension MacSelectionStyleTests {

    /// The web hovers rows with its `--theme-bg-hover` token; Mac tinted them with a 4% accent
    /// wash instead, which read blue. Theme.bgHover mirrors the web token per theme.
    func testHoverUsesTheWebHoverTokenNotAnAccentWash() {
        XCTAssertEqual(MacSelectionStyle.fill(isSelected: false, hovering: true), Theme.bgHover)
        XCTAssertNotEqual(MacSelectionStyle.fill(isSelected: false, hovering: true),
                          Theme.accent.opacity(0.04), "The blue accent wash is not what the web does")
    }

    func testRestingRowKeepsTheCardSurface() {
        XCTAssertEqual(MacSelectionStyle.fill(isSelected: false, hovering: false), Theme.bgSecondary)
    }

    /// Selection is carried by the border, so a selected row must not also take the hover fill.
    func testSelectedRowIgnoresHoverFill() {
        XCTAssertEqual(MacSelectionStyle.fill(isSelected: true, hovering: true), Theme.bgSecondary)
    }
}
