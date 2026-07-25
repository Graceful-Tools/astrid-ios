//  MacSelectionStyleTests.swift
//  Astrid for Mac — Task b8d1ec16: selection border must be subtle (thin), not heavy.

#if os(macOS)
import XCTest
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

    /// Hover affordance (77225941): hover is a distinct tier between normal and selected,
    /// and selected always wins over hover.
    func testHoverTier() {
        let normal = MacSelectionStyle.fill(isSelected: false, hovering: false)
        let hover = MacSelectionStyle.fill(isSelected: false, hovering: true)
        let selected = MacSelectionStyle.fill(isSelected: true, hovering: false)
        XCTAssertNotEqual(hover, normal, "Hover must be visible vs normal")
        XCTAssertNotEqual(hover, selected, "Hover must be lighter than selected")
        // Selected wins even while hovering.
        XCTAssertEqual(MacSelectionStyle.fill(isSelected: true, hovering: true), selected)
        // Border also distinguishes hover from normal.
        XCTAssertNotEqual(MacSelectionStyle.borderColor(isSelected: false, hovering: true),
                          MacSelectionStyle.borderColor(isSelected: false, hovering: false))
    }
}
#endif
