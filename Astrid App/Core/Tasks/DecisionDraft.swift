//  DecisionDraft.swift
//  A decision being written in task details (ADEV-189): the question, its options and, if wanted,
//  a trade-off grid rated in traffic-light colours. It becomes ordinary markdown in the format
//  astrid-web `docs/DECISIONS.md` describes, posted as a comment or added to the description, so
//  every app draws it as tappable cards and a coloured grid, and the answer is the reply a tapped
//  card posts (`DecisionThread`). Nothing about a decision is kept anywhere but that text.

import AstridCore
import Foundation

struct DecisionDraft: Equatable {
    struct Option: Equatable, Identifiable {
        let id = UUID()
        var text = ""
    }

    struct Criterion: Equatable, Identifiable {
        let id = UUID()
        var name = ""
        /// What it means, optional (ADEV-231): one line of the key under the grid.
        var detail = ""
    }

    struct CellKey: Hashable {
        let option: UUID
        let criterion: UUID
    }

    enum Problem: Equatable {
        case noQuestion
        case tooFewOptions
        /// A reason with no colour: the table would no longer read as a grid.
        case reasonWithoutRating
    }

    var question = ""
    var options: [Option] = [Option(), Option()]
    /// The option marked `(recommended)`, if any.
    var recommended: UUID?
    var criteria: [Criterion] = []
    private(set) var cells: [CellKey: DecisionGrid.Cell] = [:]

    /// The grid's columns, as web's guide asks: three to five; one or two are allowed.
    static let maxCriteria = 5

    func cell(option: UUID, criterion: UUID) -> DecisionGrid.Cell {
        cells[CellKey(option: option, criterion: criterion)] ?? .init(rating: nil, text: "")
    }

    mutating func set(_ cell: DecisionGrid.Cell, option: UUID, criterion: UUID) {
        cells[CellKey(option: option, criterion: criterion)] = cell
    }

    // MARK: - Writing

    private var namedOptions: [Option] { options.filter { !Self.line($0.text).isEmpty } }
    private var namedCriteria: [Criterion] { criteria.filter { !Self.line($0.name).isEmpty } }

    /// Only the cells of options and criteria that are written down.
    private var keptCells: [DecisionGrid.Cell] {
        namedOptions.flatMap { o in namedCriteria.map { cell(option: o.id, criterion: $0.id) } }
    }

    var problem: Problem? {
        if Self.line(question).isEmpty { return .noQuestion }
        if namedOptions.count < 2 { return .tooFewOptions }
        if keptCells.contains(where: { $0.rating == nil && !Self.line($0.text).isEmpty }) {
            return .reasonWithoutRating
        }
        return nil
    }

    /// A grid only once a cell has a colour; criteria alone add nothing.
    var grid: DecisionGrid? {
        guard !namedCriteria.isEmpty, keptCells.contains(where: { $0.rating != nil }) else { return nil }
        return DecisionGrid(optionLabel: "Option", criteria: namedCriteria.map { Self.line($0.name) },
                            options: namedOptions.map { o in
                                DecisionGrid.Option(name: Self.line(o.text), cells: namedCriteria.map { c in
                                    let cell = cell(option: o.id, criterion: c.id)
                                    return .init(rating: cell.rating, text: Self.line(cell.text))
                                })
                            })
    }

    var markdown: String {
        var lines = ["**Decision:** \(Self.line(question))", ""]
        for (i, option) in namedOptions.enumerated() {
            let mark = option.id == recommended ? " (recommended)" : ""
            lines.append("- **\(i + 1).** \(Self.line(option.text))\(mark)")
        }
        if let grid {
            lines += ["", grid.markdown]
            let key = namedCriteria.filter { !Self.line($0.detail).isEmpty }
                .map { "- **\(Self.line($0.name)):** \(Self.line($0.detail))" }
            if !key.isEmpty { lines += [""] + key }
        }
        return lines.joined(separator: "\n")
    }

    /// `description` with the decision after what is already there.
    func appended(to description: String) -> String { Self.append(markdown, to: description) }

    /// `description` with `markdown` after what is already there, a blank line between.
    static func append(_ markdown: String, to description: String) -> String {
        let kept = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? markdown : description.replacingOccurrences(
            of: "\\s+$", with: "", options: .regularExpression) + "\n\n" + markdown
    }

    /// One line: a decision's question, options and cells never span lines.
    private static func line(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
