import SwiftUI
import XCTest
@testable import Astrid_App

/// ADEV-194 — in the dark theme the list row filled with `bgPrimary` (#111827), the screen's own
/// background, while the board card used #1F2937. Both now read astrid-core's `surface`, and
/// `surface-hover` when selected, from one place — the same tokens web's row and card use.
final class TaskCardFillTests: XCTestCase {

    func testADEV194DarkListRowAndBoardCardReadSurface() {
        XCTAssertEqual(TaskCardFill.color(theme: "dark", isSelected: false), AstridTokens.dark.surface)
        XCTAssertNotEqual(TaskCardFill.color(theme: "dark", isSelected: false), AstridTokens.dark.bgPrimary)
    }

    func testADEV194DarkSelectedReadsSurfaceHover() {
        XCTAssertEqual(TaskCardFill.color(theme: "dark", isSelected: true), AstridTokens.dark.surfaceHover)
    }

    func testADEV194LightStaysSurfaceWhite() {
        XCTAssertEqual(TaskCardFill.color(theme: "light", isSelected: false), AstridTokens.light.surface)
        XCTAssertEqual(TaskCardFill.color(theme: "light", isSelected: false), Theme.bgPrimary)
        // The selected board card was white before ADEV-194 and stays white; its stroke marks it.
        XCTAssertEqual(TaskCardFill.color(theme: "light", isSelected: true), AstridTokens.light.surface)
    }

    func testADEV194OceanKeepsTranslucentWhiteSolidWhenSelected() {
        XCTAssertEqual(TaskCardFill.color(theme: "ocean", isSelected: false),
                       AstridTokens.ocean.surface.opacity(0.8))
        XCTAssertEqual(TaskCardFill.color(theme: "ocean", isSelected: true), AstridTokens.ocean.surface)
    }
}
