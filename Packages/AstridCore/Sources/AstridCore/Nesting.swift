import Foundation

/// Task ids (`AWTD-1007`) and what a dragged or indented row's drop means — astrid-core's
/// `identifierParse`, `identifierFormat` and `nesting` rules (core `b88ec47`, AITD-645).
///
/// All three are synchronous rule-door questions, so a search box can ask as the person types and
/// a drop handler can ask while it runs.

/// An identifier read into its parts: the key uppercased, the sequence ≥ 1.
public struct CoreIdentifier: Decodable, Equatable, Sendable {
    public let key: String
    public let sequence: Int

    public init(key: String, sequence: Int) {
        self.key = key
        self.sequence = sequence
    }
}

/// One row as the nesting rule reads it: its id and its parent. That is all the decision turns
/// on, so a drop does not encode every field of every task.
public struct NestingRow: Encodable, Equatable, Sendable {
    public let id: String
    public let parentTaskId: String?

    public init(id: String, parentTaskId: String?) {
        self.id = id
        self.parentTaskId = parentTaskId
    }
}

/// Where a drop happened.
public enum NestingZone: Equatable, Sendable {
    /// On a row: become its subtask.
    case on(String)
    /// On the insertion line between rows: top level, there.
    case line
    /// In the leading gutter: up one level.
    case outdent
    /// The keyboard's indent, among these row ids in the order they are drawn.
    case indent([String])
}

/// What the drop means for the dragged row's parent.
public enum NestingOutcome: Equatable, Sendable {
    case makeSubtask(parentId: String)
    case moveToTopLevel
    case reorderOnly
    case none
}

extension CoreRules {
    /// `KEY-N` into its parts, or `nil` when `value` is not an identifier — a title, `#12`, a uuid.
    /// `nil` is the core's answer, not a failure: a title is a normal thing to type into a search.
    public static func identifierParse(_ value: String) -> CoreIdentifier? {
        try? ask(IdentifierParseRequest(value: value), as: CoreIdentifier?.self) ?? nil
    }

    /// Parts somebody else holds, written out: `awtd` + 1007 → `AWTD-1007`. Derives nothing —
    /// the server is the only minter.
    public static func identifierFormat(key: String, sequence: Int) throws -> String {
        try ask(IdentifierFormatRequest(key: key, sequence: sequence), as: String.self)
    }

    /// What dropping `draggedId` in `zone` means. `rows` must include the dragged row — the core
    /// refuses (`badRequest`) rather than answer `none` for a row it was never shown.
    public static func nesting(
        zone: NestingZone, draggedId: String, rows: [NestingRow]
    ) throws -> NestingOutcome {
        let answer = try ask(NestingRequest(zone: zone, draggedId: draggedId, tasks: rows),
                             as: NestingAnswer.self)
        switch answer.outcome {
        case "makeSubtask":
            guard let parentId = answer.parentId else {
                throw CoreFailure(kind: .badRequest, message: "makeSubtask without a parentId",
                                  status: nil, id: draggedId)
            }
            return .makeSubtask(parentId: parentId)
        case "moveToTopLevel": return .moveToTopLevel
        case "reorderOnly": return .reorderOnly
        case "none": return .none
        default:
            throw CoreFailure(kind: .unknown, message: "unknown nesting outcome \(answer.outcome)",
                              status: nil, id: draggedId)
        }
    }
}

private struct IdentifierParseRequest: Encodable {
    let kind = "identifierParse"
    let value: String
}

private struct IdentifierFormatRequest: Encodable {
    let kind = "identifierFormat"
    let key: String
    let sequence: Int
}

private struct NestingRequest: Encodable {
    let kind = "nesting"
    let zone: NestingZone
    let draggedId: String
    let tasks: [NestingRow]
}

private struct NestingAnswer: Decodable {
    let outcome: String
    let parentId: String?
}

extension NestingZone: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .line:
            var container = encoder.singleValueContainer()
            try container.encode("line")
        case .outdent:
            var container = encoder.singleValueContainer()
            try container.encode("outdent")
        case .on(let id):
            var container = encoder.singleValueContainer()
            try container.encode(["on": id])
        case .indent(let ids):
            var container = encoder.singleValueContainer()
            try container.encode(["indent": ids])
        }
    }
}
