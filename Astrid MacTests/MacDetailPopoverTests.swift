//  MacDetailPopoverTests.swift
//  Astrid for Mac — Task 2766d9a4: the detail pop-out shows only for a single selection.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacDetailPopoverTests: XCTestCase {

    func testVisibleOnlyForSingleSelection() {
        XCTAssertFalse(MacDetailPopover.isVisible(selectionCount: 0), "No selection → no pop-out (full-width list)")
        XCTAssertTrue(MacDetailPopover.isVisible(selectionCount: 1))
        XCTAssertFalse(MacDetailPopover.isVisible(selectionCount: 3), "Multi-select → no single-task detail")
    }
}
#endif

// MARK: - Unfold-from-the-arrow reveal (reported: a fade is not what we want)

extension MacDetailPopoverTests {

    /// Regression for the macOS console storm where scaling the detail's
    /// PlatformTextFieldAdaptors emitted invalid min/max length warnings.
    func testRevealMaskKeepsContentAtFullScale() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        let visible = MacDetailRevealMask.visibleRect(in: bounds, progress: 0.5, anchorY: 0.25)

        XCTAssertEqual(visible.width, 200, accuracy: 0.001)
        XCTAssertEqual(visible.height, 432, accuracy: 0.001)
        XCTAssertEqual(visible.minX, bounds.minX, accuracy: 0.001)
        XCTAssertEqual(visible.minY + visible.height * 0.25,
                       bounds.minY + bounds.height * 0.25,
                       accuracy: 0.001)
    }

    func testRevealDoesNotScaleAppKitBackedTextFields() throws {
        let source = try String(contentsOf: macDetailPopoverSource(), encoding: .utf8)
        let modifier = try XCTUnwrap(source.components(separatedBy: "struct MacDetailReveal: ViewModifier").last?
            .components(separatedBy: "struct MacDetailRevealMask").first)

        XCTAssertFalse(modifier.contains(".scaleEffect("),
                       "Scaling the detail hierarchy produces PlatformTextFieldAdaptor constraint warnings")
        XCTAssertTrue(modifier.contains(".clipShape(MacDetailRevealMask("))
    }

    /// Collapsed, the panel is about as tall as the arrow — that is what makes the motion read as
    /// the ARROW widening rather than a whole box appearing.
    func testCollapsedStateIsArrowSized() {
        let collapsed = MacDetailReveal.verticalScale(progress: 0)
        XCTAssertGreaterThan(collapsed, 0, "Must stay visible — a zero scale would blink out")
        XCTAssertLessThan(collapsed, 0.2, "Collapsed height should read as the arrow, not a panel")
    }

    func testFullyRevealedIsFullSize() {
        XCTAssertEqual(MacDetailReveal.verticalScale(progress: 1), 1, accuracy: 0.001)
    }

    func testRevealGrowsMonotonically() {
        var previous = MacDetailReveal.verticalScale(progress: 0)
        for step in stride(from: CGFloat(0.1), through: 1, by: 0.1) {
            let current = MacDetailReveal.verticalScale(progress: step)
            XCTAssertGreaterThan(current, previous, "Growth must not reverse mid-animation")
            previous = current
        }
    }

    /// The fold origin follows the selected ROW, so the panel appears to come out of that task.
    func testAnchorFollowsTheSelectedRow() {
        // Content spanning 100...900 (global); a row centred at 300 is a quarter of the way down.
        XCTAssertEqual(MacDetailReveal.anchor(rowMidY: 300, contentMinY: 100, contentHeight: 800),
                       0.25, accuracy: 0.001)
        XCTAssertEqual(MacDetailReveal.anchor(rowMidY: 500, contentMinY: 100, contentHeight: 800),
                       0.5, accuracy: 0.001)
    }

    /// A row scrolled out of view has no measurement — unfold from the middle rather than the top.
    func testAnchorFallsBackToTheMiddle() {
        XCTAssertEqual(MacDetailReveal.anchor(rowMidY: nil, contentMinY: 0, contentHeight: 800),
                       0.5, accuracy: 0.001)
        XCTAssertEqual(MacDetailReveal.anchor(rowMidY: 300, contentMinY: 0, contentHeight: 0),
                       0.5, accuracy: 0.001, "A zero-height content area must not divide by zero")
    }

    /// Rows above or below the content area clamp into it rather than anchoring off-panel.
    func testAnchorClampsIntoThePanel() {
        XCTAssertEqual(MacDetailReveal.anchor(rowMidY: -500, contentMinY: 0, contentHeight: 800), 0)
        XCTAssertEqual(MacDetailReveal.anchor(rowMidY: 5_000, contentMinY: 0, contentHeight: 800), 1)
    }

    private func macDetailPopoverSource() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/Views/MacDetailPopover.swift")
    }
}
