//  DecisionDisplay.swift
//  How a comment's decision is laid out (ADEV-229). A decision with a trade-off grid of the same
//  options draws as its question and the grid alone, each row the option to choose; the cards are
//  only for a decision with no grid. Jon, 2026-11-23: two sets of the same options — cards to tap
//  and rows to weigh — was one too many; the grid is where the choice is made.
//
//  The markdown is unchanged (astrid-web `docs/DECISIONS.md`), so an agent's question and the
//  composer's draw the same way, on iOS and the Mac, and a client that has not caught up still
//  shows both. Rows and options are matched by position, as the grid numbers its rows 1, 2, 3 in
//  the options' order; a grid with a different number of rows is not the same choice and is left
//  as it was.

import AstridCore

enum DecisionDisplay: Equatable {
    case block(DecisionBlock)
    /// The question, then the grid; row `n` chooses `decision.options[n]`.
    case choosableGrid(Decision, TradeOff)

    static func arrange(_ blocks: [DecisionBlock]) -> [DecisionDisplay] {
        var shown: [DecisionDisplay] = []
        var absorbed = Set<Int>()
        for (index, block) in blocks.enumerated() where !absorbed.contains(index) {
            guard case .decision(let decision) = block,
                  let gridIndex = grid(after: index, in: blocks),
                  case .tradeOff(let grid) = blocks[gridIndex],
                  grid.rows.count == decision.options.count
            else {
                shown.append(.block(block))
                continue
            }
            absorbed.insert(gridIndex)
            shown.append(.choosableGrid(decision, grid))
        }
        return shown
    }

    /// The first grid after `index` and before the next decision.
    private static func grid(after index: Int, in blocks: [DecisionBlock]) -> Int? {
        for i in blocks.indices.dropFirst(index + 1) {
            switch blocks[i] {
            case .tradeOff: return i
            case .decision: return nil
            case .markdown: continue
            }
        }
        return nil
    }
}
