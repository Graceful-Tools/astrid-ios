import Foundation

/// A decision's trade-off grid as data an editor can change: read out of a task's description and
/// written back into the same place, with the prose around it untouched (ADEV-189, web ADEV-180).
///
/// **Ported from astrid-web `lib/decision-grid.ts`** (`parseGrid`, `serializeGrid`, `replaceGrid`),
/// checked case for case against its generated `contracts/fixtures/decision-grid.json`
/// (`DecisionGridTests`). Which tokens are ratings is the core's (`ratingKey`), as in `Decisions`.
/// Starting a decision and recording the choice stay on the server (`POST …/decisions`,
/// `POST …/decide`), so the builder and the decided record are not copied here.
///
/// The grid never gets a score or total column (web ADEV-178): the person decides.
public struct DecisionGrid: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        /// The rating token as written (`++`, `~`, `🟢`), or nil for an empty cell.
        public var rating: String?
        /// The concrete reason after the token.
        public var text: String

        public init(rating: String?, text: String) {
            self.rating = rating
            self.text = text
        }

        /// `<rating> <text>`, either part left out when empty.
        public var markdown: String {
            [rating, text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    public struct Option: Equatable, Sendable {
        /// Without its "1." marker: the grid numbers its rows itself.
        public var name: String
        /// One per criterion.
        public var cells: [Cell]

        public init(name: String, cells: [Cell]) {
            self.name = name
            self.cells = cells
        }
    }

    /// The top-left header, "Option" by default.
    public var optionLabel: String
    public var criteria: [String]
    public var options: [Option]

    public init(optionLabel: String, criteria: [String], options: [Option]) {
        self.optionLabel = optionLabel
        self.criteria = criteria
        self.options = options
    }

    /// A grid and the text on either side of it, exactly as written.
    public struct Found: Equatable, Sendable {
        public let grid: DecisionGrid
        public let before: String
        public let after: String
    }

    // MARK: - Writing

    /// A header, a separator, then one numbered row per option. No score column, ever.
    public var markdown: String {
        let header = [optionLabel.isEmpty ? "Option" : optionLabel] + criteria
        var lines = [
            "| " + header.map(Self.escape).joined(separator: " | ") + " |",
            "|" + header.map { _ in "---" }.joined(separator: "|") + "|",
        ]
        for (i, option) in options.enumerated() {
            let cells = criteria.indices.map { c in
                c < option.cells.count ? option.cells[c] : Cell(rating: nil, text: "")
            }
            let row = ["\(i + 1). \(option.name)"] + cells.map(\.markdown)
            lines.append("| " + row.map(Self.escape).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// `markdown` with its grid replaced by `grid`; nil when it has no grid to replace.
    public static func replace(in markdown: String, with grid: DecisionGrid) -> String? {
        guard let found = parse(markdown) else { return nil }
        return [found.before, grid.markdown, found.after].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: - Reading

    /// The first trade-off grid in `markdown` outside code, or nil when there is none — including
    /// when the first table is not a grid (a cell with no rating).
    public static func parse(_ markdown: String) -> Found? {
        guard !markdown.isEmpty else { return nil }
        let lines = markdown.components(separatedBy: "\n")
        var fence: String?
        var i = 0
        while i < lines.count - 1 {
            defer { i += 1 }
            let line = lines[i]
            let opener = fenceRun(line)
            if let open = fence {
                if let opener, opener.first == open.first, opener.count >= open.count,
                   trim(line) == opener {
                    fence = nil
                }
                continue
            }
            if let opener {
                fence = opener
                continue
            }
            guard trim(line).hasPrefix("|") else { continue }
            let separator = trim(lines[i + 1]).hasPrefix("|") ? splitRow(lines[i + 1]) : []
            guard !separator.isEmpty, separator.allSatisfy(isSeparatorCell) else { continue }

            var end = i + 2
            while end < lines.count, trim(lines[end]).hasPrefix("|") { end += 1 }
            let header = splitRow(line)
            let body = lines[(i + 2)..<end].map(splitRow)
            guard header.count >= 2, !body.isEmpty, isTradeoffGrid(body) else { return nil }

            var options: [Option] = []
            for row in body {
                var cells: [Cell] = []
                for c in 1..<header.count {
                    guard let cell = readCell(c < row.count ? row[c] : "") else { return nil }
                    cells.append(cell)
                }
                options.append(Option(name: rowName(row.first ?? ""), cells: cells))
            }
            return Found(grid: DecisionGrid(optionLabel: header[0], criteria: Array(header.dropFirst()),
                                            options: options),
                         before: lines[0..<i].joined(separator: "\n"),
                         after: lines[end...].joined(separator: "\n"))
        }
        return nil
    }

    // MARK: - Ratings

    /// The five plain tokens a picker offers, worst to best, from the core's rating key. The emoji
    /// forms are read and kept as written, but not offered.
    public static var ratingTokens: [String] {
        ratingKey.filter { $0.token.allSatisfy(\.isASCII) }.map(\.token)
    }

    /// What a token means, worst (0) to best (4), from the core; nil for anything else.
    public static func rank(of token: String) -> Int? {
        ratingKey.first { $0.token == token }?.rank
    }

    private struct RatingEntry: Decodable, Sendable {
        let token: String
        let rank: Int
    }

    private struct RatingKeyRequest: Encodable {
        let kind = "ratingKey"
    }

    /// The core's key, worst to best. The tokens are a contract with web
    /// (`PRODUCT_CONTRACT.md` §8); the fallback is only for a core that cannot answer.
    private static let ratingKey: [RatingEntry] = {
        if let key = try? CoreRules.ask(RatingKeyRequest(), as: [RatingEntry].self), !key.isEmpty {
            return key
        }
        return [("--", 0), ("-", 1), ("🔴", 1), ("~", 2), ("🟡", 2), ("+", 3), ("🟢", 3), ("++", 4)]
            .map { RatingEntry(token: $0.0, rank: $0.1) }
    }()

    /// Tokens longest first, so `--` is never read as `-` nor `++` as `+`.
    private static let parseOrder: [String] = ratingKey.map(\.token).sorted { $0.utf8.count > $1.utf8.count }

    /// A cell's leading token and the words after it. The token must end the cell or be followed by
    /// whitespace: `++cheap` carries no rating.
    private static func parseRating(_ cell: String) -> Cell? {
        let text = trim(cell)
        for token in parseOrder where text.hasPrefix(token) {
            let rest = text.dropFirst(token.count)
            if rest.isEmpty || rest.first?.isWhitespace == true {
                return Cell(rating: token, text: trim(String(rest)))
            }
        }
        return nil
    }

    private static func readCell(_ raw: String) -> Cell? {
        trim(raw).isEmpty ? Cell(rating: nil, text: "") : parseRating(raw)
    }

    /// Every non-empty body cell after the first column is rated, at least one is, and they are
    /// not all a bare `-` (somebody's empty template). Mirrors the core's `is_tradeoff_grid`.
    private static func isTradeoffGrid(_ rows: [[String]]) -> Bool {
        var rated = 0
        var allBareDash = true
        for row in rows {
            for cell in row.dropFirst() where !trim(cell).isEmpty {
                guard let r = parseRating(cell) else { return false }
                rated += 1
                if !(r.rating == "-" && r.text.isEmpty) { allBareDash = false }
            }
        }
        return rated > 0 && !allBareDash
    }

    // MARK: - Table text

    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func escape(_ text: String) -> String {
        trim(text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|"))
    }

    /// `:?-{3,}:?`
    private static func isSeparatorCell(_ cell: String) -> Bool {
        var body = Substring(cell)
        if body.hasPrefix(":") { body = body.dropFirst() }
        if body.hasSuffix(":") { body = body.dropLast() }
        return body.count >= 3 && body.allSatisfy { $0 == "-" }
    }

    /// Split a row on unescaped pipes, unescaping `\|` and `\\` in each cell.
    private static func splitRow(_ line: String) -> [String] {
        var body = Array(trim(line))
        if body.first == "|" { body.removeFirst() }
        var cells: [String] = []
        var cell = ""
        var ended = false
        var i = 0
        while i < body.count {
            let ch = body[i]
            if ch == "\\", i + 1 < body.count, body[i + 1] == "|" || body[i + 1] == "\\" {
                i += 1
                cell.append(body[i])
                ended = false
            } else if ch == "|" {
                cells.append(trim(cell))
                cell = ""
                ended = i == body.count - 1
            } else {
                cell.append(ch)
                ended = false
            }
            i += 1
        }
        if !ended { cells.append(trim(cell)) }
        return cells
    }

    /// A fence opener at the start of a line: three or more backticks or tildes.
    private static func fenceRun(_ line: String) -> String? {
        let body = line.drop { $0 == " " || $0 == "\t" }
        guard let first = body.first, first == "`" || first == "~" else { return nil }
        let run = body.prefix { $0 == first }
        return run.count >= 3 ? String(run) : nil
    }

    /// A row's option name without the marker its writer put in front (`A. Lisbon` → `Lisbon`):
    /// web's `^\s*(?:[A-Za-z]|\d{1,2})(?:[.):](?:\s+|$)|\s*$)`.
    private static func rowName(_ text: String) -> String {
        let body = text.drop { $0.isWhitespace }
        let digits = body.prefix { $0.isASCII && $0.isNumber }.count
        let lengths: [Int]
        if digits >= 2 { lengths = [2, 1] }
        else if digits == 1 || body.first.map({ $0.isASCII && $0.isLetter }) == true { lengths = [1] }
        else { return trim(text) }
        for length in lengths {
            let rest = body.dropFirst(length)
            if let p = rest.first, ".):".contains(p) {
                let after = rest.dropFirst()
                if after.isEmpty || after.first?.isWhitespace == true { return trim(String(after)) }
            }
            if trim(String(rest)).isEmpty { return "" }
        }
        return trim(text)
    }
}
