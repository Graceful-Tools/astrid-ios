import Foundation

/// Two shapes of ordinary markdown that the Apple apps draw as something richer than text, so an
/// agent can lay a choice in front of someone in a way they can answer on a phone.
///
/// A **decision** (AITD-579): a `**Decision:**` line followed by a list whose items start with a
/// bold letter. Each option draws as a card; tapping one replies with its letter and words.
///
///     **Decision:** Which way?
///     - **A.** Go with the format (recommended)
///     - **B.** iOS first
///
/// A **trade-off grid** (AITD-578): a table whose cells, after the first column, each start with a
/// rating — `++` `+` `~` `-` `--`, or 🟢 🟡 🔴 — then a short reason. Options are rows, criteria
/// are columns, and each cell draws on its rating's colour.
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
    /// Upper case, as the reply carries it.
    public let letter: String
    /// The option's words, marks and references kept, without the letter or "(recommended)".
    public let label: [MarkdownInline]
    /// The same words as plain text, for the reply.
    public let text: String
    public let recommended: Bool

    public init(letter: String, label: [MarkdownInline], text: String, recommended: Bool) {
        self.letter = letter
        self.label = label
        self.text = text
        self.recommended = recommended
    }

    /// What tapping the card posts. It leads with the letter, which is what `chosenLetter` and a
    /// human typing "A" both rely on.
    public var reply: String { text.isEmpty ? letter : "\(letter) — \(text)" }
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

    /// The option a reply picks: the letter it starts with, alone or followed by a space or
    /// punctuation. "A", "b", "C — Something else" and "A. go" choose; "Also…" does not.
    public static func chosenLetter(in reply: String, letters: [String]) -> String? {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.isLetter else { return nil }
        let rest = trimmed.dropFirst()
        if let next = rest.first, next.isLetter || next.isNumber { return nil }
        let letter = String(first).uppercased()
        return letters.contains(letter) ? letter : nil
    }

    // MARK: - Decisions

    private static func decision(question: MarkdownBlock, options: MarkdownBlock) -> Decision? {
        guard case .paragraph(let inlines) = question,
              case .text(let lead)? = inlines.first, lead.bold, !lead.code,
              lead.text.trimmingCharacters(in: .whitespaces).lowercased() == "decision:",
              case .list(_, _, let items) = options else { return nil }
        let parsed = items.compactMap(option)
        guard parsed.count == items.count, parsed.count >= 2 else { return nil }
        return Decision(question: trimmingLeadingSpace(Array(inlines.dropFirst())), options: parsed)
    }

    private static func option(_ item: MarkdownListItem) -> DecisionOption? {
        guard item.checked == nil,
              case .paragraph(let inlines)? = item.blocks.first,
              case .text(let lead)? = inlines.first, lead.bold, !lead.code,
              let letter = optionLetter(lead.text) else { return nil }
        var label = trimmingLeadingSpace(Array(inlines.dropFirst()))
        let recommended = stripRecommended(&label)
        return DecisionOption(letter: letter, label: label, text: plainText(label),
                              recommended: recommended)
    }

    /// "A", "A." "A)" or "A:" — one letter, then at most one mark.
    private static func optionLetter(_ text: String) -> String? {
        var chars = Array(text.trimmingCharacters(in: .whitespaces))
        if let last = chars.last, ".):".contains(last) { chars.removeLast() }
        guard chars.count == 1, chars[0].isLetter, chars[0].isASCII else { return nil }
        return String(chars[0]).uppercased()
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
