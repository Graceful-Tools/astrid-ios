//  DecisionViews.swift
//  A decision's options as cards you tap (AITD-579), and a trade-off grid of coloured cells
//  (AITD-578) — on iOS and on the Mac. Options are numbered, criteria lettered (AITD-585).
//
//  Both are ordinary markdown that `Decisions` (AstridCore) picks out of the rendered blocks;
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

struct TradeOffGridView: View {
    let grid: TradeOff
    let style: MarkdownStyle
    let inline: ([MarkdownInline]) -> Text

    /// A cell wraps within these before the grid grows sideways and scrolls (AITD-585), so a
    /// word is never broken across lines to squeeze one more column onto a phone.
    private let cellWidth: ClosedRange<CGFloat> = 84...150
    private let optionWidth: ClosedRange<CGFloat> = 64...120

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing * 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .center, horizontalSpacing: 3, verticalSpacing: 3) {
                    GridRow {
                        ForEach(Array(grid.header.enumerated()), id: \.offset) { index, cell in
                            header(cell, column: index)
                        }
                    }
                    ForEach(Array(grid.rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            option(row, number: index + 1)
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                                ratedCell(cell)
                            }
                        }
                    }
                }
            }
            legend
        }
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
            .wrapped(within: column == 0 ? optionWidth : cellWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: column == 0 ? .leading : .center)
    }

    /// Numbered like the cards, whatever marker the row was written with.
    private func option(_ row: TradeOffRow, number: Int) -> some View {
        (Text(verbatim: "\(number). ") + inline(row.name)).font(style.small.bold())
            .padding(.horizontal, 6).padding(.vertical, 6)
            .wrapped(within: optionWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func ratedCell(_ cell: TradeOffCell) -> some View {
        Text(MarkdownRendering.attributed(cell.reason, defaultColor: TradeOffPalette.text(for: cell.rating),
                                          referenceFont: nil))
            .font(style.small)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .wrapped(within: cellWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(cell.rating.map(TradeOffPalette.fill) ?? style.text.opacity(0.05)))
            .accessibilityLabel(Text(TradeOffPalette.label(for: cell.rating) + ". "
                                     + Decisions.plainText(cell.reason)))
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

/// Lays its content out at a definite width inside `range` — its own width when that is
/// narrower, never wider than it is offered — and reports the height that width needs.
///
/// `frame(minWidth:maxWidth:)` cannot do this inside a sideways ScrollView: the scroll view
/// measures with no width, the frame passes none on, and the text answers with its one-line
/// height. The row kept that height while the text drew wrapped at `range.upperBound`, so
/// everything after the first line was clipped (AITD-588).
private struct WrapWithin: Layout {
    let range: ClosedRange<CGFloat>

    private func width(for proposal: ProposedViewSize, _ child: LayoutSubview) -> CGFloat {
        let natural = child.sizeThatFits(.unspecified).width
        return min(natural, proposal.width ?? range.upperBound, range.upperBound)
            .clamped(to: range)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = width(for: proposal, child)
        return CGSize(width: width, height: child.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

private extension View {
    func wrapped(within range: ClosedRange<CGFloat>) -> some View {
        WrapWithin(range: range) { self }
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
