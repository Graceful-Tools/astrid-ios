//  MacTradeOffGridLayoutTests.swift
//  Regression guard for Task AITD-590 — "[mac] same issue on mac that we fixed on ios.
//  traffliclight should be exapnd to height to include all the text".
//
//  The Mac draws the trade-off grid with the same shared `TradeOffGridView` as iOS, inside the
//  same sideways ScrollView, so it had the same clipping: each reason was measured as one line,
//  drawn wrapped, and cut off after the first (AITD-588). The fix is that shared view; this
//  holds it on the Mac's own host and fonts, in a comment bubble that hugs its content.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

@MainActor
final class MacTradeOffGridLayoutTests: XCTestCase {

    private func height(of source: String, width: CGFloat = 700) -> CGFloat {
        let view = MacMarkdownText(source: source, fillsWidth: false).frame(width: width)
        return NSHostingView(rootView: view).fittingSize.height
    }

    private func grid(reason: String, option: String = "Rust core") -> String {
        """
        | Option | Cost | Speed |
        |---|---|---|
        | A. \(option) | ++ \(reason) | + fast |
        | B. Swift | -- two codebases | - slower |
        """
    }

    func testAITD590_aLongReasonMakesItsRowTallerOnMac() {
        let short = height(of: grid(reason: "one codebase"))
        let long = height(of: grid(reason: String(repeating: "one codebase for every platform ", count: 6)))

        XCTAssertGreaterThan(long, short + 60, "the row grows to fit its reason (short \(short), long \(long))")
    }

    func testAITD590_aLongOptionNameMakesItsRowTallerOnMac() {
        let short = height(of: grid(reason: "one codebase"))
        let long = height(of: grid(reason: "one codebase",
                                   option: String(repeating: "Rust core shared by everyone ", count: 5)))

        XCTAssertGreaterThan(long, short + 60, "the row grows to fit its option (short \(short), long \(long))")
    }
}
#endif
