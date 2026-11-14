//  MarkdownTableLayout.swift
//  A markdown table that is too wide for its column scrolls sideways (AITD-659).
//
//  SwiftUI's `Grid` squeezed every table into the width it was given, so a wide one broke its words
//  across lines and could not be read. This lays the table out the way the trade-off grid does
//  (`TradeOffGridLayout`, AITD-588): every cell measured at the width it is drawn at, so text
//  inside a sideways scroller wraps instead of clipping. Unlike the grid, each column keeps its own
//  width, because a plain table's columns are not alike.

import SwiftUI

/// The widths a table's columns are drawn at.
///
/// A column is as wide as its widest cell, up to `cap`; past that its text wraps. When the table is
/// given less room than that, the columns give width back in proportion, but never below `floor`
/// (or their own width, if narrower). A table whose floors do not fit scrolls (`overflows`).
struct MarkdownTableMetrics: Equatable {
    static let cap: CGFloat = 200
    static let floor: CGFloat = 88

    let widths: [CGFloat]

    /// `available` is nil inside a sideways scroller, which offers no width at all.
    init(natural: [CGFloat], available: CGFloat?, spacing: CGFloat) {
        let full = natural.map { min($0, Self.cap) }
        let floors = full.map { min($0, Self.floor) }
        let gaps = spacing * CGFloat(max(natural.count - 1, 0))
        guard let available, available.isFinite else { widths = full; return }
        let room = available - gaps
        let wanted = full.reduce(0, +), least = floors.reduce(0, +)
        if wanted <= room || wanted == least {
            widths = full
        } else if least >= room {
            widths = floors
        } else {
            let share = (room - least) / (wanted - least)
            widths = zip(floors, full).map { $0 + ($1 - $0) * share }
        }
    }

    /// The narrowest the table can be drawn without scrolling.
    static func leastWidth(natural: [CGFloat], spacing: CGFloat) -> CGFloat {
        natural.map { min($0, cap, floor) }.reduce(0, +) + spacing * CGFloat(max(natural.count - 1, 0))
    }
}

/// `columns` subviews to a row, header first, then ONE more subview — the rule under the header,
/// drawn across the whole table.
///
/// `scrolls` says where it is: in a sideways scroller every column takes its full width; in place,
/// its ideal width is the narrowest it can be drawn at, so `ViewThatFits` keeps it in place
/// whenever the floors fit and only reaches for the scroller when they do not.
struct MarkdownTableLayout: Layout {
    let columns: Int
    let spacing: CGFloat
    let scrolls: Bool

    struct Cache {
        var natural: [CGFloat]
        var placed: (width: CGFloat?, widths: [CGFloat], heights: [CGFloat])?
    }

    func makeCache(subviews: Subviews) -> Cache {
        let cells = cellCount(subviews)
        var natural = Array(repeating: CGFloat(0), count: columns)
        for index in 0..<cells {
            natural[index % columns] = max(natural[index % columns], subviews[index].sizeThatFits(.unspecified).width)
        }
        return Cache(natural: natural)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    private func cellCount(_ subviews: Subviews) -> Int {
        columns > 0 ? max(subviews.count - 1, 0) : 0
    }

    private func rows(_ subviews: Subviews) -> Int {
        columns > 0 ? (cellCount(subviews) + columns - 1) / columns : 0
    }

    /// The column widths and row heights for a proposed width, measured once per width.
    private func sizes(_ width: CGFloat?, _ subviews: Subviews, _ cache: inout Cache) -> ([CGFloat], [CGFloat]) {
        if let placed = cache.placed, placed.width == width { return (placed.widths, placed.heights) }
        let widths = MarkdownTableMetrics(natural: cache.natural, available: scrolls ? nil : width,
                                          spacing: spacing).widths
        let cells = cellCount(subviews)
        let heights = (0..<rows(subviews)).map { row in
            (0..<columns).map { column -> CGFloat in
                let index = row * columns + column
                guard index < cells else { return 0 }
                return subviews[index].sizeThatFits(ProposedViewSize(width: widths[column], height: nil)).height
            }.max() ?? 0
        }
        cache.placed = (width, widths, heights)
        return (widths, heights)
    }

    private func ruleHeight(_ subviews: Subviews) -> CGFloat {
        subviews.last.map { $0.sizeThatFits(.unspecified).height } ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard columns > 0, !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(max(columns - 1, 0))
        if !scrolls && proposal.width == nil {
            // The ideal size `ViewThatFits` compares: the narrowest this can be without scrolling.
            let (_, heights) = sizes(MarkdownTableMetrics.leastWidth(natural: cache.natural, spacing: spacing),
                                     subviews, &cache)
            return CGSize(width: MarkdownTableMetrics.leastWidth(natural: cache.natural, spacing: spacing),
                          height: total(heights) + ruleHeight(subviews) + spacing)
        }
        let (widths, heights) = sizes(proposal.width, subviews, &cache)
        return CGSize(width: widths.reduce(0, +) + gaps, height: total(heights) + ruleHeight(subviews) + spacing)
    }

    private func total(_ heights: [CGFloat]) -> CGFloat {
        heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard columns > 0, !subviews.isEmpty else { return }
        let (widths, heights) = sizes(proposal.width ?? bounds.width, subviews, &cache)
        let cells = cellCount(subviews)
        let rule = ruleHeight(subviews)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            var x = bounds.minX
            for (column, width) in widths.enumerated() {
                let index = row * columns + column
                guard index < cells else { break }
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: height))
                x += width + spacing
            }
            y += height + spacing
            if row == 0 {
                // The rule under the header, across every column, with a gap below it as above.
                subviews[subviews.count - 1].place(
                    at: CGPoint(x: bounds.minX, y: y),
                    proposal: ProposedViewSize(width: widths.reduce(0, +) + spacing * CGFloat(max(columns - 1, 0)),
                                               height: rule))
                y += rule + spacing
            }
        }
    }
}
