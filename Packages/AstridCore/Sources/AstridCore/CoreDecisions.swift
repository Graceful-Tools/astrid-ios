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
/// asked over the rules door: `decision`, and the `tradeoffGrid` block `renderMarkdown` returns for
/// a rated table (AWTD-1626). The core is a port of web's
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

    /// The core's label key for a rating (`"veryGood"`), which is also the case's name.
    init?(key: String) {
        guard let rating = Self.allCases.first(where: { "\($0)" == key }) else { return nil }
        self = rating
    }
}

public struct TradeOff: Equatable, Sendable {
    /// The first cell names the options column; the rest are the criteria.
    public let header: [[MarkdownInline]]
    public let rows: [TradeOffRow]
}

public struct TradeOffRow: Equatable, Sendable {
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

    /// The grid the core picked out of a table (AWTD-1626), in the shape the views draw.
    public static func tradeOff(_ block: MarkdownBlock) -> TradeOff? {
        guard case .tradeoffGrid(let header, let rows) = block else { return nil }
        return TradeOff(header: header, rows: rows.map { row in
            TradeOffRow(name: row.name, cells: row.cells.map { cell in
                TradeOffCell(rating: cell.rating.flatMap(TradeOffRating.init(key:)), reason: cell.inlines)
            })
        })
    }
}
