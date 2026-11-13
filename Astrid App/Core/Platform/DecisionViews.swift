//  DecisionViews.swift
//  A decision's options as cards you tap (AITD-579), and a trade-off grid of coloured cells
//  (AITD-578) — on iOS and on the Mac. Options are numbered, criteria lettered (AITD-585).
//
//  Both are ordinary markdown that astrid-core picks out (`Decisions`, AITD-641);
//  `MarkdownView` hands them here. What a card does when tapped belongs to the comment thread
//  around it, which passes a `DecisionResponse` down; without one the cards only show the options.

import AstridCore
import SwiftUI

private struct DecisionResponseKey: EnvironmentKey {
    static let defaultValue: DecisionResponse? = nil
}

extension EnvironmentValues {
    /// Set per comment by a thread (AITD-579); `nil` — a description, your own question — draws
    /// the cards without taking a tap.
    var decisionResponse: DecisionResponse? {
        get { self[DecisionResponseKey.self] }
        set { self[DecisionResponseKey.self] = newValue }
    }
}

// MARK: - Decision cards

struct DecisionCardsView: View {
    let decision: Decision
    let style: MarkdownStyle
    let inline: ([MarkdownInline]) -> Text
    @Environment(\.decisionResponse) private var response

    private var state: DecisionResponse.State { DecisionResponse.state(response, for: decision) }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing * 2) {
            if !decision.question.isEmpty {
                inline(decision.question).font(style.body.bold())
            }
            ForEach(Array(decision.options.enumerated()), id: \.offset) { _, option in
                card(option)
            }
        }
    }

    private func card(_ option: DecisionOption) -> some View {
        let chosen = state == .chosen(option.number)
        let dimmed = !chosen && state != .open && state != .readOnly
        return Button { response?.tap(option, in: decision) } label: {
            HStack(alignment: .firstTextBaseline, spacing: style.markerSpacing * 1.5) {
                Text(verbatim: "\(option.number)")
                    .font(style.body.bold())
                    .foregroundColor(chosen ? .white : Theme.accent)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Circle().fill(chosen ? Theme.accent : Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 4) {
                    inline(option.label).font(style.body)
                    if option.recommended {
                        Text(NSLocalizedString("decision.recommended", comment: "Badge on the option the asker recommends"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.accent)
                    }
                }
                Spacer(minLength: 0)
                if chosen {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(style.text.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(chosen ? Theme.accent : style.text.opacity(0.15), lineWidth: chosen ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that greys the chosen card too, the one that should stand out.
        .allowsHitTesting(state == .open)
        .accessibilityIdentifier("decision.option.\(option.number)")
    }
}

// MARK: - Trade-off grid

/// Global frames of content that scrolls sideways: the iPad task panel's swipe-to-close
/// leaves a swipe that starts on one to it (AITD-594). Only content that is wider than its
/// space reports itself; a grid that fits has nothing to scroll (AITD-595).
enum SidewaysScrollRegions: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func reportsSidewaysScrollRegion(_ scrolls: Bool = true) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: SidewaysScrollRegions.self,
                                   value: scrolls ? [proxy.frame(in: .global)] : [])
        })
    }
}

struct TradeOffGridView: View {
    let grid: TradeOff
    let style: MarkdownStyle
    let inline: ([MarkdownInline]) -> Text
    /// Drawn by `TradeOffGridFullScreenView` (AITD-595): wider cells, no scroller of its own (the
    /// full-screen view scrolls both ways), and no control to open full screen again.
    var fullScreen = false
    /// The width the grid is shown in, when the caller knows it better than the grid can: inside
    /// the full-screen view's two-way scroller the grid's own width is its content's.
    var availableWidth: CGFloat?

    /// A cell wraps within these before the grid grows sideways and scrolls (AITD-585), so a
    /// word is never broken across lines to squeeze one more column onto a phone. The options
    /// column may run wider than a criterion (AITD-591), up to a third of the width (AITD-592).
    private var cellWidth: ClosedRange<CGFloat> { TradeOffGridMetrics.cellWidth(fullScreen: fullScreen) }
    @State private var measured: CGFloat?
    @State private var contentWidth: CGFloat?
    @State private var showsFullScreen = false
    private var available: CGFloat? { availableWidth ?? measured }
    private var optionWidth: ClosedRange<CGFloat> { TradeOffGridMetrics.optionWidth(available: available) }
    /// Is there anything to scroll? Only then does a sideways drag belong to the grid (AITD-595).
    private var scrollsSideways: Bool {
        guard let contentWidth, let measured else { return false }
        return contentWidth > measured + 0.5
    }

    /// The header's; a row written with fewer cells is padded with empty ones.
    private var columns: Int { max(grid.header.count, 1 + (grid.rows.map(\.cells.count).max() ?? 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing * 2) {
            if fullScreen {
                table
            } else {
                fullScreenButton
                ScrollView(.horizontal, showsIndicators: false) {
                    table.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                }
                .reportsSidewaysScrollRegion(scrollsSideways)
            }
            legend
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured = $0 }
        #if os(iOS)
        .fullScreenCover(isPresented: $showsFullScreen) {
            TradeOffGridFullScreenView(grid: grid, style: style)
        }
        #else
        .sheet(isPresented: $showsFullScreen) {
            TradeOffGridFullScreenView(grid: grid, style: style)
                .frame(minWidth: 720, minHeight: 480)
        }
        #endif
    }

    private var table: some View {
        TradeOffGridLayout(columns: columns, optionWidth: optionWidth, cellWidth: cellWidth,
                           spacing: 3) {
            ForEach(0..<columns, id: \.self) { column in
                header(column < grid.header.count ? grid.header[column] : [], column: column)
            }
            ForEach(Array(grid.rows.enumerated()), id: \.offset) { index, row in
                option(row, number: index + 1)
                ForEach(0..<columns - 1, id: \.self) { column in
                    ratedCell(column < row.cells.count ? row.cells[column] : nil)
                }
            }
        }
    }

    /// Web's "⤢ Full screen" above every grid (AITD-595, PRODUCT_CONTRACT §8).
    private var fullScreenButton: some View {
        Button { showsFullScreen = true } label: {
            Label(NSLocalizedString("tasks.tradeoff_grid.full_screen", comment: ""),
                  systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain)
        .font(style.small)
        .foregroundColor(style.muted)
    }

    /// The options column's name as written; each criterion after it under its letter, A, B, C.
    private func header(_ cell: [MarkdownInline], column: Int) -> some View {
        let title = column == 0
            ? inline(cell)
            : Text(verbatim: Decisions.columnLetter(column - 1) + "  ").foregroundColor(style.muted)
                + inline(cell)
        return title.font(style.small.bold())
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: column == 0 ? .leading : .center)
    }

    /// Numbered like the cards, whatever marker the row was written with.
    private func option(_ row: TradeOffRow, number: Int) -> some View {
        (Text(verbatim: "\(number). ") + inline(row.name)).font(style.small.bold())
            .padding(.horizontal, 6).padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// `nil` past the end of a row written with fewer cells than the header, drawn as an empty one.
    private func ratedCell(_ cell: TradeOffCell?) -> some View {
        Text(MarkdownRendering.attributed(cell?.reason ?? [], defaultColor: TradeOffPalette.text(for: cell?.rating),
                                          referenceFont: nil))
            .font(style.small)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(cell?.rating.map(TradeOffPalette.fill) ?? style.text.opacity(0.05)))
            .accessibilityLabel(Text(TradeOffPalette.label(for: cell?.rating) + ". "
                                     + Decisions.plainText(cell?.reason ?? [])))
    }

    /// The colour key, for the ratings this grid uses, worst to best.
    private var legend: some View {
        let used = Set(grid.rows.flatMap { $0.cells.compactMap(\.rating) })
        let ratings = TradeOffRating.allCases.filter(used.contains)
        let key = ForEach(ratings, id: \.self) { rating in
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(TradeOffPalette.fill(rating))
                    .frame(width: 10, height: 10)
                Text(TradeOffPalette.label(for: rating)).fixedSize()
            }
        }
        // One line where it fits; on a narrow phone, two columns' worth stacked.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { key }
            VStack(alignment: .leading, spacing: 2) { key }
        }
        .font(style.small)
        .foregroundColor(style.muted)
    }
}

/// A trade-off grid on a screen of its own (AITD-595, web AWTD-1534): the grid and its colour key
/// in a view that scrolls both ways, with wider cells, closed with ✕. Drawn in the system's own
/// colours rather than the caller's, which may be a sender's bubble with white text.
struct TradeOffGridFullScreenView: View {
    let grid: TradeOff
    let style: MarkdownStyle
    @Environment(\.dismiss) private var dismiss
    @Environment(\.taskIdentifierLinks) private var identifiers
    @State private var width: CGFloat?

    private var plain: MarkdownStyle {
        var plain = style
        plain.text = .primary
        plain.muted = .secondary
        return plain
    }

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                TradeOffGridView(grid: grid, style: plain, inline: inline, fullScreen: true,
                                 availableWidth: width)
                    .padding()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text(NSLocalizedString("misc.close", comment: "")))
                }
            }
        }
    }

    private func inline(_ inlines: [MarkdownInline]) -> Text {
        Text(MarkdownRendering.attributed(inlines, defaultColor: .primary, referenceFont: nil,
                                          identifiers: identifiers))
    }
}

/// The grid's column widths and row heights (AITD-591): every criterion column as wide as the
/// widest, within `cellWidth`; the options column its own width, within `optionWidth`, which may
/// be wider; every option row as tall as the tallest at those widths, so all of its text fits.
/// Row 0 is the header and keeps its own height.
struct TradeOffGridMetrics: Equatable {
    let widths: [CGFloat]
    let heights: [CGFloat]

    /// The options column's range, as web's (PRODUCT_CONTRACT §8): its longest name between 96
    /// and 192, never more than a third of the `available` width, and wrapping past that (AITD-592).
    /// A criterion cell's range: 84-150 in a comment (AITD-585), and at least web's 9rem with room
    /// to grow in the full-screen view (AITD-595).
    static func cellWidth(fullScreen: Bool) -> ClosedRange<CGFloat> {
        fullScreen ? 144...240 : 84...150
    }

    static func optionWidth(available: CGFloat?) -> ClosedRange<CGFloat> {
        let floor: CGFloat = 96
        guard let available, available > 0 else { return floor...192 }
        return floor...max(floor, min(192, (available / 3).rounded(.down)))
    }

    init(columns: Int, rows: Int, optionWidth: ClosedRange<CGFloat>, cellWidth: ClosedRange<CGFloat>,
         naturalWidth: (_ row: Int, _ column: Int) -> CGFloat,
         height: (_ row: Int, _ column: Int, _ width: CGFloat) -> CGFloat) {
        func widest(_ columns: Range<Int>) -> CGFloat {
            columns.flatMap { column in (0..<rows).map { naturalWidth($0, column) } }.max() ?? 0
        }
        let option = widest(0..<min(1, columns)).clamped(to: optionWidth)
        let cell = widest(min(1, columns)..<columns).clamped(to: cellWidth)
        let widths = (0..<columns).map { $0 == 0 ? option : cell }
        let natural = (0..<rows).map { row in
            (0..<columns).map { height(row, $0, widths[$0]) }.max() ?? 0
        }
        let body = natural.dropFirst().max() ?? 0
        self.widths = widths
        self.heights = natural.indices.map { $0 == 0 ? natural[0] : body }
    }
}

/// Lays the grid out row by row, `columns` subviews to a row, at `TradeOffGridMetrics`' sizes.
///
/// Every cell is measured at the definite width it will be drawn at. SwiftUI's `Grid` could not do
/// this inside a sideways ScrollView: the scroll view measures with no width, and text answers
/// with its one-line height while drawing wrapped, so everything after the first line was clipped
/// (AITD-588). Nor could it give every row the tallest row's height (AITD-591).
struct TradeOffGridLayout: Layout {
    let columns: Int
    let optionWidth: ClosedRange<CGFloat>
    let cellWidth: ClosedRange<CGFloat>
    let spacing: CGFloat

    func makeCache(subviews: Subviews) -> TradeOffGridMetrics? { nil }

    private func metrics(_ subviews: Subviews, _ cache: inout TradeOffGridMetrics?) -> TradeOffGridMetrics {
        if let cache { return cache }
        let rows = columns > 0 ? (subviews.count + columns - 1) / columns : 0
        func cell(_ row: Int, _ column: Int) -> LayoutSubview? {
            let index = row * columns + column
            return index < subviews.count ? subviews[index] : nil
        }
        let metrics = TradeOffGridMetrics(
            columns: columns, rows: rows, optionWidth: optionWidth, cellWidth: cellWidth,
            naturalWidth: { cell($0, $1)?.sizeThatFits(.unspecified).width ?? 0 },
            height: { cell($0, $1)?.sizeThatFits(ProposedViewSize(width: $2, height: nil)).height ?? 0 })
        cache = metrics
        return metrics
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout TradeOffGridMetrics?) -> CGSize {
        let metrics = metrics(subviews, &cache)
        func total(_ sizes: [CGFloat]) -> CGFloat {
            sizes.reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        }
        return CGSize(width: total(metrics.widths), height: total(metrics.heights))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout TradeOffGridMetrics?) {
        let metrics = metrics(subviews, &cache)
        var y = bounds.minY
        for (row, height) in metrics.heights.enumerated() {
            var x = bounds.minX
            for (column, width) in metrics.widths.enumerated() {
                let index = row * columns + column
                guard index < subviews.count else { return }
                subviews[index].place(at: CGPoint(x: x, y: y),
                                      proposal: ProposedViewSize(width: width, height: height))
                x += width + spacing
            }
            y += height + spacing
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Google Docs' palette, which is what a hand-made traffic-light table in a doc uses: the two
/// extremes dark with white text, the three between light with dark text. Fixed rather than
/// themed, so a red cell reads as red in dark mode too.
enum TradeOffPalette {
    static func fill(_ rating: TradeOffRating) -> Color {
        switch rating {
        case .veryPoor: return Color(red: 0.80, green: 0.00, blue: 0.00)   // dark red 1  #CC0000
        case .poor: return Color(red: 0.88, green: 0.40, blue: 0.40)       // light red 1 #E06666
        case .mixed: return Color(red: 1.00, green: 0.85, blue: 0.40)      // light yellow 1 #FFD966
        case .good: return Color(red: 0.58, green: 0.77, blue: 0.49)       // light green 1 #93C47D
        case .veryGood: return Color(red: 0.22, green: 0.46, blue: 0.11)   // dark green 2 #38761D
        }
    }

    static func text(for rating: TradeOffRating?) -> Color {
        switch rating {
        case .veryPoor?, .veryGood?: return .white
        case .poor?, .mixed?, .good?: return Color.black.opacity(0.87)
        case nil: return .primary
        }
    }

    static func label(for rating: TradeOffRating?) -> String {
        switch rating {
        case .veryPoor?: return NSLocalizedString("tradeoff.very_poor", comment: "Darkest red cell")
        case .poor?: return NSLocalizedString("tradeoff.poor", comment: "Red cell")
        case .mixed?: return NSLocalizedString("tradeoff.mixed", comment: "Yellow cell")
        case .good?: return NSLocalizedString("tradeoff.good", comment: "Green cell")
        case .veryGood?: return NSLocalizedString("tradeoff.very_good", comment: "Darkest green cell")
        case nil: return NSLocalizedString("tradeoff.unrated", comment: "A cell left empty")
        }
    }
}
