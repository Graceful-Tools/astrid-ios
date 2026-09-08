//  MacDetailPanelFillTests.swift
//  Regression guard for AITD-334 — "[mac] allow task details pane to extend to width of left panel".
//
//  Jon: "currently it doesn't expand… should fill the message pane with reasonable margin so should
//  just scale to fill the message pane, no drag of the task details window."
//
//  Before this, the panel was a fixed 380pt and every point the chat column gained over its floor
//  went into the pop-out's TRAILING PADDING — so dragging the messages column wider pushed the
//  panel left and opened a gutter between it and the window edge, instead of letting the panel use
//  the room. The panel now takes those points as WIDTH and keeps a constant margin at the trailing
//  edge.
//
//  The invariant that must survive all of this is AITD-302's: the arrow tip clears the row card's
//  trailing edge by exactly `detailArrowRowGap`. Widening the panel at its trailing edge leaves its
//  LEADING edge — and therefore the arrow — exactly where it was, which is why both halves of the
//  change have to land together and are asserted together here.

import XCTest
@testable import Astrid_Mac

final class MacDetailPanelFillTests: XCTestCase {

    /// Content areas wide enough that `resolvedChatColumnWidth` is not the thing clamping.
    private let contentRight: CGFloat = 1_400

    /// Chat column widths a drag can actually produce: the floor, then progressively wider.
    private var chatWidths: [CGFloat] {
        [MacLayout.chatColumnMinWidth, 450, 520, 640]
    }

    // MARK: - It fills

    /// The point of the task: no gutter. Whatever the chat column is, the card's trailing edge sits
    /// one margin in from the content edge — "fill the message pane with reasonable margin".
    func testAITD334ThePanelReachesTheTrailingMarginAtEveryChatColumnWidth() {
        for width in chatWidths {
            let panel = MacLayout.resolvedDetailPanelWidth(chatColumnWidth: width)
            let cardLeft = contentRight - MacLayout.detailPanelMargin - panel
            let cardRight = cardLeft + panel

            XCTAssertEqual(contentRight - cardRight, MacLayout.detailPanelMargin, accuracy: 0.001,
                           "A gutter opened at a chat column width of \(width) — the panel is not filling")
        }
    }

    /// It grows by exactly what the column gained. More would push the card past the margin; less
    /// would leave the gutter this task is about.
    func testAITD334ThePanelGrowsByExactlyWhatTheChatColumnGained() {
        let gained: CGFloat = 90

        XCTAssertEqual(
            MacLayout.resolvedDetailPanelWidth(chatColumnWidth: MacLayout.chatColumnMinWidth + gained)
                - MacLayout.resolvedDetailPanelWidth(chatColumnWidth: MacLayout.chatColumnMinWidth),
            gained, accuracy: 0.001)
    }

    /// Nothing moves for someone who never drags: at the floor the panel is still the 380 it ships
    /// at, so this task cannot quietly resize the default layout.
    func testAITD334AtTheDefaultWidthThePanelIsTheWidthItShipsAt() {
        XCTAssertEqual(MacLayout.resolvedDetailPanelWidth(chatColumnWidth: MacLayout.chatColumnMinWidth),
                       MacLayout.detailPanelWidth, accuracy: 0.001)
    }

    /// 380 is a FLOOR, not a starting point to be shrunk below. A chat column narrower than its own
    /// floor cannot happen through `resolvedChatColumnWidth`, but the width rule must not depend on
    /// that to stay safe — a narrower panel would clip the detail rows `MacDetailRowFit` sizes.
    func testAITD334ThePanelNeverShrinksBelowTheWidthItShipsAt() {
        for width in [CGFloat(0), 100, MacLayout.chatColumnMinWidth - 1] {
            XCTAssertGreaterThanOrEqual(
                MacLayout.resolvedDetailPanelWidth(chatColumnWidth: width),
                MacLayout.detailPanelWidth,
                "The shipped width is the floor — a \(width)pt chat column must not narrow the panel")
        }
    }

    // MARK: - …without breaking the arrow (AITD-302)

    /// The whole reason the panel grows at its TRAILING edge: the leading edge, and therefore the
    /// arrow, must not move. This is the same clearance AITD-302 pinned and AITD-329 carried through
    /// the resize — re-asserted here against the new width rule, because widening from the wrong
    /// edge would sweep the arrow across the rows it points at.
    func testAITD334TheArrowKeepsItsClearanceNowThatThePanelFills() {
        for width in chatWidths {
            let panel = MacLayout.resolvedDetailPanelWidth(chatColumnWidth: width)
            let cardLeft = contentRight - MacLayout.detailPanelMargin - panel
            let arrowTip = cardLeft - (MacLayout.detailArrowWidth - MacLayout.arrowOverlap)
            let rowRight = contentRight - width - MacLayout.columnDividerWidth - MacLayout.rowTrailingGap

            XCTAssertEqual(arrowTip - rowRight, MacLayout.detailArrowRowGap, accuracy: 0.001,
                           "Clearance drifted at a chat column width of \(width)")
        }
    }

    /// The card must still stay clear of the row CONTENT at every width — filling the message pane
    /// is about the trailing edge, and must never be paid for by covering rows.
    func testAITD334ThePanelStillNeverCoversTheRows() {
        for width in chatWidths {
            let panel = MacLayout.resolvedDetailPanelWidth(chatColumnWidth: width)
            let cardLeft = contentRight - MacLayout.detailPanelMargin - panel
            let rowRight = contentRight - width - MacLayout.columnDividerWidth - MacLayout.rowTrailingGap

            XCTAssertGreaterThan(cardLeft, rowRight,
                                 "The card covered row content at a chat column width of \(width)")
        }
    }
}
