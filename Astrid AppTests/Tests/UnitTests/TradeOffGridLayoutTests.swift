//  TradeOffGridLayoutTests.swift
//  Regression guard for Task AITD-588 — "Make row height in decision matrix grow to support
//  content".
//
//  AITD-585 put the grid in a sideways ScrollView so a cell wraps within 84–150pt instead of
//  breaking words. A horizontal scroll view sizes its height from its content measured with no
//  width, and a `frame(maxWidth:)` passes that missing width straight on: each reason was
//  measured as one line, then drawn wrapped at 150pt, so the rows kept their one-line height and
//  the scroll view clipped the rest.

import XCTest
import SwiftUI
@testable import Astrid_App

@MainActor
final class TradeOffGridLayoutTests: XCTestCase {

    private func height(of source: String, width: CGFloat = 360) -> CGFloat {
        let host = UIHostingController(rootView: MarkdownText(source: source))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func grid(reason: String) -> String {
        """
        | Option | Cost | Speed |
        |---|---|---|
        | A. Rust core | ++ \(reason) | + fast |
        | B. Swift | -- two codebases | - slower |
        """
    }

    func testAITD588_aLongReasonMakesItsRowTaller() {
        let short = height(of: grid(reason: "one codebase"))
        let long = height(of: grid(reason: String(repeating: "one codebase for every platform ", count: 6)))

        // Six repeats wrap to many lines at 150pt; a row that grew for them adds several lines'
        // height, a row that stayed one line high adds nothing.
        XCTAssertGreaterThan(long, short + 60, "the row grows to fit its reason (short \(short), long \(long))")
    }

    func testAITD588_aLongOptionNameMakesItsRowTaller() {
        let short = height(of: grid(reason: "one codebase"))
        let longName = height(of: """
            | Option | Cost | Speed |
            |---|---|---|
            | A. \(String(repeating: "Rust core shared by everyone ", count: 5)) | ++ one codebase | + fast |
            | B. Swift | -- two codebases | - slower |
            """)

        XCTAssertGreaterThan(longName, short + 60, "the row grows to fit its option (short \(short), long \(longName))")
    }
}

// MARK: - Task AITD-591 — "make the traffic light rows and columns all the same height (e.g.
// distribute) but make sure that all the text fits. the option (first column) can be wider if
// needed"
//
// The grid sized each row and column to its own content, so one long reason made one tall row
// and one wide column beside short ones. Every option row is now as tall as the tallest, and
// every rated column as wide as the widest; the options column keeps its own width.

@MainActor
final class TradeOffGridUniformTests: XCTestCase {

    private func height(of source: String) -> CGFloat {
        let host = UIHostingController(rootView: MarkdownText(source: source))
        return host.sizeThatFits(in: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)).height
    }

    private func grid(_ first: String, _ second: String) -> String {
        """
        | Option | Cost | Speed |
        |---|---|---|
        | A. Rust core | ++ \(first) | + fast |
        | B. Swift | -- \(second) | - slower |
        """
    }

    private let long = String(repeating: "one codebase for every platform ", count: 6)

    func testAITD591_oneTallRowMakesEveryRowThatTall() {
        let oneLong = height(of: grid(long, "two codebases"))
        let bothLong = height(of: grid(long, long))

        // With equal rows the short row is already as tall as the long one, so making it long
        // too changes nothing; with rows sized to their own text it adds several lines.
        XCTAssertEqual(oneLong, bothLong, accuracy: 1,
                       "rows share the tallest row's height (one long \(oneLong), both long \(bothLong))")
    }

    func testAITD591_columnsShareTheWidestWidthAndRowsTheTallestHeight() {
        // Column 0 is the options column; 1 and 2 are criteria. Natural widths and the height
        // each cell needs at a width, as a layout would measure them.
        let natural: [[CGFloat]] = [[50, 40, 40], [100, 150, 60], [70, 90, 60]]
        let metrics = TradeOffGridMetrics(
            columns: 3, rows: 3, optionWidth: 64...180, cellWidth: 84...150,
            naturalWidth: { natural[$0][$1] },
            height: { row, column, width in row == 1 && column == 1 ? 80 : (width < 90 ? 40 : 20) })

        XCTAssertEqual(metrics.widths, [100, 150, 150], "criteria share the widest; options keep their own")
        XCTAssertEqual(metrics.heights[1], metrics.heights[2], "option rows share one height")
        XCTAssertEqual(metrics.heights[1], 80, "the tallest cell's text fits")
        XCTAssertEqual(metrics.heights[0], 20, "the header row keeps its own height")
    }

    func testAITD591_theOptionsColumnMayBeWiderThanACriterion() {
        let metrics = TradeOffGridMetrics(
            columns: 2, rows: 2, optionWidth: 64...180, cellWidth: 84...150,
            naturalWidth: { _, column in column == 0 ? 400 : 30 },
            height: { _, _, _ in 20 })

        XCTAssertEqual(metrics.widths, [180, 84])
    }
}

// MARK: - Task AITD-592 — "Trade-off grid: option rows one height and criteria columns one
// width, all text fitting (follow web AWTD-1536)"
//
// Web's contract (PRODUCT_CONTRACT §8): the option column fits its longest name between about
// 96 and 192, and never more than a third of the width the grid is given; past that it wraps.

final class TradeOffGridOptionWidthTests: XCTestCase {

    func testAITD592_theOptionColumnRunsFrom96To192() {
        XCTAssertEqual(TradeOffGridMetrics.optionWidth(available: 1000), 96...192)
        XCTAssertEqual(TradeOffGridMetrics.optionWidth(available: nil), 96...192, "unmeasured: the plain range")
    }

    func testAITD592_theOptionColumnTakesAtMostAThirdOfTheWidth() {
        XCTAssertEqual(TradeOffGridMetrics.optionWidth(available: 390), 96...130, "a phone: a third of 390")
        XCTAssertEqual(TradeOffGridMetrics.optionWidth(available: 240), 96...96, "never below the floor")
    }
}

// MARK: - Task AITD-595 — "Trade-off grid: a sideways drag scrolls the grid instead of closing the
// task, and the grid opens full screen (iOS half of web AWTD-1534)"
//
// Web's full-screen grid draws wider cells (at least ~9rem) in a view that scrolls both ways.

final class TradeOffGridFullScreenTests: XCTestCase {

    func testAITD595_inlineCellsKeepTheirWidth() {
        XCTAssertEqual(TradeOffGridMetrics.cellWidth(fullScreen: false), 84...150)
    }

    func testAITD595_fullScreenCellsAreAtLeastNineRemWide() {
        let full = TradeOffGridMetrics.cellWidth(fullScreen: true)
        XCTAssertGreaterThanOrEqual(full.lowerBound, 144)
        XCTAssertGreaterThan(full.upperBound, TradeOffGridMetrics.cellWidth(fullScreen: false).upperBound)
    }
}
