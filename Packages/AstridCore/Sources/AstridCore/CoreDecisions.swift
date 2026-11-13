import Foundation

/// Two shapes of ordinary markdown that the Apple apps draw as something richer than text, so an
/// agent can lay a choice in front of someone in a way they can answer on a phone.
///
/// A **decision** (AITD-579): a `**Decision:**` line followed by a list whose items start with a
/// bold letter or number. Each option draws as a card numbered in order (AITD-585); tapping one
/// replies with its number and words.
///
///     **Decision:** Which way?
///     - **A.** Go with the format (recommended)
///     - **B.** iOS first
///
/// A **trade-off grid** (AITD-578): a table whose cells, after the first column, each start with a
/// rating — `++` `+` `~` `-` `--`, or 🟢 🟡 🔴 — then a short reason. Options are rows, numbered
/// like the cards; criteria are columns, lettered A, B, C (AITD-585); each cell draws on its
/// rating's colour.
///
///     | Option   | Cost            | Risk  |
///     |----------|-----------------|-------|
///     | A. Rust  | ++ one codebase | ~ new |
///
/// **What is a decision and what is a grid is astrid-core's** (`astrid_rules::decisions`, AITD-641),
/// asked over the rules door: `decision`, `tradeoffGrid` and `ratingKey`. The core is a port of web's
/// `lib/comment-formats.ts`, checked against `contracts/fixtures/decisions.json`. This file only
/// turns its answer into the inlines the views draw; before it, Swift recognised both shapes itself
/// (Decision.swift) and drifted from the web — options written with mixed list markers (`-`, `*`,
/// `1.`) were cards on the web and plain lists here. The format is a contract with the web
/// (astrid-web `docs/PRODUCT_CONTRACT.md` §8).
public enum DecisionBlock: Equatable, Sendable {
    case markdown(MarkdownBlock)
    case decision(Decision)
    case tradeOff(TradeOff)
}

public struct Decision: Equatable, Sendable {
    public let question: [MarkdownInline]
    public let options: [DecisionOption]

    public init(question: [MarkdownInline], options: [DecisionOption]) {
        self.question = question
        self.options = options
    }
}

public struct DecisionOption: Equatable, Sendable {
    /// The marker as the asker wrote it, upper case: "A", or "1". A reply leading with it still
    /// chooses this option.
    public let letter: String
    /// Its place in the list, from 1 — what the card shows and the reply leads with (AITD-585).
    public let number: Int
    /// The option's words, marks and references kept, without the letter or "(recommended)".
    public let label: [MarkdownInline]
    /// The same words as plain text, for the reply.
    public let text: String
    public let recommended: Bool

    public init(letter: String, number: Int, label: [MarkdownInline], text: String, recommended: Bool) {
        self.letter = letter
        self.number = number
        self.label = label
        self.text = text
        self.recommended = recommended
    }

    /// What tapping the card posts. It leads with the number, which is what `chosenNumber` and a
    /// human typing "1" both rely on.
    public var reply: String { text.isEmpty ? "\(number)" : "\(number) — \(text)" }
}

/// How an option does on one criterion, worst to best — the core's `rank`, 0 to 4.
public enum TradeOffRating: Int, CaseIterable, Equatable, Sendable {
    case veryPoor, poor, mixed, good, veryGood
}

public struct TradeOff: Equatable, Sendable {
    /// The first cell names the options column; the rest are the criteria.
    public let header: [[MarkdownInline]]
    public let rows: [TradeOffRow]
}

public struct TradeOffRow: Equatable, Sendable {
    /// The first cell as written.
    public let option: [MarkdownInline]
    /// The option without the marker its writer put in front ("A. Lisbon" → "Lisbon"); the grid
    /// numbers its rows itself, like the cards (AITD-585).
    public let name: [MarkdownInline]
    /// One per criterion.
    public let cells: [TradeOffCell]
}

public struct TradeOffCell: Equatable, Sendable {
    /// `nil` for a cell left empty.
    public let rating: TradeOffRating?
    /// The words after the rating.
    public let reason: [MarkdownInline]
}

public enum Decisions {

    /// `source` rendered, with its decision and each trade-off grid picked out by astrid-core.
    public static func blocks(source: String) -> [DecisionBlock] {
        guard let answer = try? CoreRules.ask(DecisionRequest(text: source), as: CoreDecision?.self)
        else { return grids(CoreRules.markdown(source)) }
        let question = paragraph(answer.prompt)
        let options = answer.options.map { option -> DecisionOption in
            let label = paragraph(option.text)
            return DecisionOption(letter: option.letter, number: option.number, label: label,
                                  text: plainText(label), recommended: option.recommended)
        }
        return markdown(answer.before)
            + [.decision(Decision(question: question, options: options))]
            + markdown(answer.after)
    }

    /// `blocks` with each trade-off grid picked out; everything else unchanged. For blocks with no
    /// source of their own — a quote's, a list item's — where a decision is never read, as on web.
    public static func grids(_ blocks: [MarkdownBlock]) -> [DecisionBlock] {
        blocks.map { block in tradeOff(block).map(DecisionBlock.tradeOff) ?? .markdown(block) }
    }

    /// The number of the option a reply picks: the number it starts with, or the letter the asker
    /// wrote, alone or followed by a space or punctuation. "2 — Wait", "1. go", "b" and
    /// "C — Something else" choose; "Also…", "2nd thoughts" and "10 minutes" do not, and neither do
    /// "Béatrice doit vérifier" or "2ème avis": the lead must end at something that is not a letter
    /// or number in any script. Mirrors the core's `chosen_number`, which the rules door does not
    /// expose; `DecisionTests` runs the core fixture's replies through it.
    public static func chosenNumber(in reply: String, options: [DecisionOption]) -> Int? {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = trimmed.prefix { ($0.isLetter || $0.isNumber) && $0.isASCII }
        guard !lead.isEmpty, trimmed.dropFirst(lead.count).first.map({ $0.isLetter || $0.isNumber }) != true
        else { return nil }
        if let number = Int(lead) {
            return options.contains { $0.number == number } ? number : nil
        }
        return options.first { $0.letter == lead.uppercased() }?.number
    }

    /// The letter over a grid's criterion column, from 0: A … Z, then AA, AB, as a spreadsheet does.
    public static func columnLetter(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var index = index, name = ""
        repeat {
            name = String(letters[index % 26]) + name
            index = index / 26 - 1
        } while index >= 0
        return name
    }

    /// The words of `inlines`, marks dropped and references by name.
    public static func plainText(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let run): return run.text
            case .reference(_, let label, _): return label
            case .lineBreak: return " "
            }
        }.joined().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - The core's answers

    private struct DecisionRequest: Encodable {
        let kind = "decision"
        let text: String
    }

    private struct CoreDecision: Decodable {
        struct Option: Decodable {
            let letter: String
            let number: Int
            let text: String
            let recommended: Bool
        }
        let before: String
        let prompt: String
        let options: [Option]
        let after: String
    }

    private struct GridRequest: Encodable {
        let kind = "tradeoffGrid"
        let rows: [[String]]
    }

    private struct CoreGrid: Decodable {
        struct Rating: Decodable {
            let rating: String
            let rest: String
        }
        let isGrid: Bool
        let cells: [[Rating?]]
        let rowNames: [String]
    }

    private struct RatingKeyRequest: Encodable {
        let kind = "ratingKey"
    }

    private struct RatingEntry: Decodable {
        let token: String
        let rank: Int
    }

    /// Each rating token's place, worst to best, as the core ranks it.
    private static let ranks: [String: TradeOffRating] = {
        let key = (try? CoreRules.ask(RatingKeyRequest(), as: [RatingEntry].self)) ?? []
        return Dictionary(key.compactMap { entry in
            TradeOffRating(rawValue: entry.rank).map { (entry.token, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }()

    private static func markdown(_ source: String) -> [DecisionBlock] {
        source.isEmpty ? [] : grids(CoreRules.markdown(source))
    }

    /// The inlines of a one-paragraph piece of markdown — a prompt, an option.
    private static func paragraph(_ source: String) -> [MarkdownInline] {
        guard !source.isEmpty else { return [] }
        return CoreRules.markdown(source).flatMap { block -> [MarkdownInline] in
            if case .paragraph(let inlines) = block { return inlines }
            return []
        }
    }

    private static func tradeOff(_ block: MarkdownBlock) -> TradeOff? {
        guard case .table(_, let header, let rows) = block, header.count >= 2, !rows.isEmpty,
              let grid = try? CoreRules.ask(GridRequest(rows: rows.map { $0.map(cellText) }),
                                            as: CoreGrid.self),
              grid.isGrid, grid.cells.count == rows.count, grid.rowNames.count == rows.count
        else { return nil }
        let gridRows = zip(rows, zip(grid.cells, grid.rowNames)).map { row, answer in
            let (ratings, rowName) = answer
            let option = row.first ?? []
            let cells = row.dropFirst().enumerated().map { column, cell -> TradeOffCell in
                guard column < ratings.count, let rated = ratings[column] else {
                    return TradeOffCell(rating: nil, reason: [])
                }
                let reason = droppingLeading(cell, characters: rated.rating.count)
                return TradeOffCell(rating: ranks[rated.rating], reason: reason)
            }
            return TradeOffRow(option: option, name: name(option, as: rowName), cells: cells)
        }
        return TradeOff(header: header, rows: gridRows)
    }

    /// A cell as the core reads it: its words, with a code span kept in backticks so `` `++` ``
    /// is shown as code rather than read as a rating, as on web, which reads the cell's source.
    private static func cellText(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let run): return run.code ? "`\(run.text)`" : run.text
            case .reference(_, let label, _): return label
            case .lineBreak: return " "
            }
        }.joined()
    }

    /// The first cell without the marker the core took off it: as many characters as the core's
    /// name is shorter than the cell's words. A name the cell does not end with keeps the cell.
    private static func name(_ option: [MarkdownInline], as name: String) -> [MarkdownInline] {
        let written = plainText(trimmingLeadingSpace(option))
        guard written.hasSuffix(name) else { return option }
        return droppingLeading(option, characters: written.count - name.count)
    }

    /// `inlines` without their first `characters` characters of plain words — a rating token, a
    /// row marker — and the space around them.
    private static func droppingLeading(_ inlines: [MarkdownInline], characters: Int) -> [MarkdownInline] {
        var inlines = trimmingLeadingSpace(inlines)
        var remaining = characters
        while remaining > 0, case .text(var run)? = inlines.first, !run.code {
            if run.text.count <= remaining {
                remaining -= run.text.count
                inlines.removeFirst()
            } else {
                run.text = String(run.text.dropFirst(remaining))
                inlines[0] = .text(run)
                remaining = 0
            }
        }
        return trimmingLeadingSpace(inlines)
    }

    private static func trimmingLeadingSpace(_ inlines: [MarkdownInline]) -> [MarkdownInline] {
        var inlines = inlines
        while let first = inlines.first {
            switch first {
            case .lineBreak:
                inlines.removeFirst()
            case .text(var run) where !run.code:
                let trimmed = String(run.text.drop { $0.isWhitespace })
                if trimmed.isEmpty { inlines.removeFirst(); continue }
                run.text = trimmed
                inlines[0] = .text(run)
                return inlines
            default:
                return inlines
            }
        }
        return inlines
    }
}
