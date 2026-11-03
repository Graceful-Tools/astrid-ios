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
/// Both are recognised from the blocks `CoreRules.markdown` already returns, so text that only
/// looks close keeps rendering as the markdown it is, and a renderer that knows neither shape —
/// an older build, an email — still shows readable text. The format is a contract with the web
/// (astrid-web `docs/PRODUCT_CONTRACT.md`): change it there and here together.
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

/// How an option does on one criterion, worst to best.
public enum TradeOffRating: Int, CaseIterable, Equatable, Sendable {
    case veryPoor, poor, mixed, good, veryGood
}

public struct TradeOff: Equatable, Sendable {
    /// The first cell names the options column; the rest are the criteria.
    public let header: [[MarkdownInline]]
    public let rows: [TradeOffRow]
}

public struct TradeOffRow: Equatable, Sendable {
    public let option: [MarkdownInline]
    /// One per criterion.
    public let cells: [TradeOffCell]

    /// The option without the marker its writer put in front ("A. Lisbon" → "Lisbon"); the grid
    /// numbers its rows itself, like the cards (AITD-585).
    public var name: [MarkdownInline] { Decisions.droppingMarker(option) }
}

public struct TradeOffCell: Equatable, Sendable {
    /// `nil` for a cell left empty.
    public let rating: TradeOffRating?
    /// The words after the rating.
    public let reason: [MarkdownInline]
}

public enum Decisions {

    /// `blocks` with each decision and each trade-off grid picked out; everything else unchanged.
    public static func blocks(_ blocks: [MarkdownBlock]) -> [DecisionBlock] {
        var result: [DecisionBlock] = []
        var index = blocks.startIndex
        while index < blocks.endIndex {
            if index + 1 < blocks.endIndex,
               let decision = decision(question: blocks[index], options: blocks[index + 1]) {
                result.append(.decision(decision))
                index += 2
                continue
            }
            if let grid = tradeOff(blocks[index]) {
                result.append(.tradeOff(grid))
            } else {
                result.append(.markdown(blocks[index]))
            }
            index += 1
        }
        return result
    }

    /// The number of the option a reply picks: the number it starts with, or the letter the asker
    /// wrote, alone or followed by a space or punctuation. "2 — Wait", "1. go", "b" and
    /// "C — Something else" choose; "Also…", "2nd thoughts" and "10 minutes" do not.
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

    // MARK: - Decisions

    private static func decision(question: MarkdownBlock, options: MarkdownBlock) -> Decision? {
        guard case .paragraph(let inlines) = question,
              case .text(let lead)? = inlines.first, lead.bold, !lead.code,
              lead.text.trimmingCharacters(in: .whitespaces).lowercased() == "decision:",
              case .list(_, _, let items) = options else { return nil }
        let parsed = items.enumerated().compactMap { option($1, number: $0 + 1) }
        guard parsed.count == items.count, parsed.count >= 2 else { return nil }
        return Decision(question: trimmingLeadingSpace(Array(inlines.dropFirst())), options: parsed)
    }

    private static func option(_ item: MarkdownListItem, number: Int) -> DecisionOption? {
        guard item.checked == nil,
              case .paragraph(let inlines)? = item.blocks.first,
              case .text(let lead)? = inlines.first, lead.bold, !lead.code,
              let letter = optionLetter(lead.text) else { return nil }
        var label = trimmingLeadingSpace(Array(inlines.dropFirst()))
        let recommended = stripRecommended(&label)
        return DecisionOption(letter: letter, number: number, label: label, text: plainText(label),
                              recommended: recommended)
    }

    /// "A", "A." "A)" or "A:" — one letter or a number of up to two digits, then at most one mark.
    private static func optionLetter(_ text: String) -> String? {
        var chars = Array(text.trimmingCharacters(in: .whitespaces))
        if let last = chars.last, ".):".contains(last) { chars.removeLast() }
        guard chars.allSatisfy(\.isASCII) else { return nil }
        if chars.count == 1, chars[0].isLetter { return String(chars[0]).uppercased() }
        guard (1...2).contains(chars.count), chars.allSatisfy(\.isNumber) else { return nil }
        return String(chars)
    }

    /// `inlines` without a leading option marker — "A. ", "2) ", "C: " or a marker standing alone.
    static func droppingMarker(_ inlines: [MarkdownInline]) -> [MarkdownInline] {
        guard case .text(var run)? = inlines.first, !run.code else { return inlines }
        let text = run.text.drop { $0.isWhitespace }
        let token = text.prefix { !$0.isWhitespace }
        let alone = inlines.count == 1 && text.dropFirst(token.count).allSatisfy(\.isWhitespace)
        let marked = token.last.map { ".):".contains($0) } == true
        guard alone || marked, optionLetter(String(token)) != nil else { return inlines }
        run.text = String(text.dropFirst(token.count))
        var rest = Array(inlines.dropFirst())
        if !run.text.isEmpty { rest.insert(.text(run), at: 0) }
        return trimmingLeadingSpace(rest)
    }

    /// Takes a trailing "(recommended)" off the label and says whether it was there.
    private static func stripRecommended(_ label: inout [MarkdownInline]) -> Bool {
        guard case .text(var run)? = label.last, !run.code else { return false }
        let trimmed = run.text.trimmingCharacters(in: .whitespaces)
        let marker = "(recommended)"
        guard trimmed.lowercased().hasSuffix(marker) else { return false }
        run.text = String(trimmed.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
        label.removeLast()
        if !run.text.isEmpty { label.append(.text(run)) }
        return true
    }

    // MARK: - Trade-off grids

    private static func tradeOff(_ block: MarkdownBlock) -> TradeOff? {
        guard case .table(_, let header, let rows) = block, header.count >= 2, !rows.isEmpty else {
            return nil
        }
        var gridRows: [TradeOffRow] = []
        var meaningful = false
        for row in rows {
            var cells: [TradeOffCell] = []
            for cell in row.dropFirst() {
                if plainText(cell).trimmingCharacters(in: .whitespaces).isEmpty {
                    cells.append(TradeOffCell(rating: nil, reason: []))
                    continue
                }
                guard let rated = rated(cell) else { return nil }
                // A dash alone is how tables say "nothing here"; it cannot carry a grid by itself.
                if !(rated.rating == .poor && rated.reason.isEmpty && bareDash(cell)) { meaningful = true }
                cells.append(rated)
            }
            gridRows.append(TradeOffRow(option: row.first ?? [], cells: cells))
        }
        return meaningful ? TradeOff(header: header, rows: gridRows) : nil
    }

    private static let markers: [String: TradeOffRating] = [
        "--": .veryPoor, "-": .poor, "~": .mixed, "+": .good, "++": .veryGood,
        "🔴": .poor, "🟡": .mixed, "🟢": .good,
    ]

    /// The cell's rating and the words after it, or `nil` when it does not start with one.
    private static func rated(_ cell: [MarkdownInline]) -> TradeOffCell? {
        guard case .text(var run)? = cell.first, !run.code else { return nil }
        let text = run.text.drop { $0.isWhitespace }
        let token = text.prefix { !$0.isWhitespace }
        guard let rating = markers[String(token)] else { return nil }
        run.text = String(text.dropFirst(token.count).drop { $0.isWhitespace })
        var reason = Array(cell.dropFirst())
        if !run.text.isEmpty { reason.insert(.text(run), at: 0) }
        return TradeOffCell(rating: rating, reason: trimmingLeadingSpace(reason))
    }

    private static func bareDash(_ cell: [MarkdownInline]) -> Bool {
        plainText(cell).trimmingCharacters(in: .whitespaces) == "-"
    }

    // MARK: - Inlines

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
}
