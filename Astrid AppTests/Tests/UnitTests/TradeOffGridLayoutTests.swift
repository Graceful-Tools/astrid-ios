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
