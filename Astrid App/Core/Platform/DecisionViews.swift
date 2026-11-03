//  DecisionViews.swift
//  A decision's options as cards you tap (AITD-579), and a trade-off grid of coloured cells
//  (AITD-578) — on iOS and on the Mac.
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
    /// iOS asks before sending: a tap while scrolling must not answer for you.
    @State private var pending: DecisionOption?

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
        .confirmationDialog(
            NSLocalizedString("decision.confirm_title", comment: "Asked before a tapped option is sent"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { option in
            Button(String(format: NSLocalizedString("decision.confirm_send", comment: "Send the chosen option"),
                          option.reply)) {
                response?.choose(option)
            }
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
        }
    }

    private func card(_ option: DecisionOption) -> some View {
        let chosen = state == .chosen(option.letter)
        let dimmed = !chosen && state != .open && state != .readOnly
        return Button { tap(option) } label: {
            HStack(alignment: .firstTextBaseline, spacing: style.markerSpacing * 1.5) {
                Text(verbatim: option.letter)
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
        .accessibilityIdentifier("decision.option.\(option.letter)")
    }

    private func tap(_ option: DecisionOption) {
        guard state == .open else { return }
        #if os(iOS)
        pending = option
        #else
        // A click on the Mac is deliberate; the reply shows in the thread and can be edited.
        response?.choose(option)
        #endif
    }
}

// MARK: - Trade-off grid

struct TradeOffGridView: View {
    let grid: TradeOff
    let style: MarkdownStyle
    let inline: ([MarkdownInline]) -> Text

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing * 2) {
            Grid(alignment: .topLeading, horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    ForEach(Array(grid.header.enumerated()), id: \.offset) { _, cell in
                        inline(cell).font(style.small.bold())
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                }
                ForEach(Array(grid.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        inline(row.option).font(style.small.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6).padding(.vertical, 6)
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                            ratedCell(cell)
                        }
                    }
                }
            }
            legend
        }
    }

    private func ratedCell(_ cell: TradeOffCell) -> some View {
        Text(MarkdownRendering.attributed(cell.reason, defaultColor: TradeOffPalette.text(for: cell.rating),
                                          referenceFont: nil))
            .font(style.small)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
