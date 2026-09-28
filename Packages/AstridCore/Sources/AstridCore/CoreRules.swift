import AstridCoreBindings
import Foundation

/// The rules door: astrid-core's pure contracts, asked synchronously.
///
/// Every answer depends on the request alone — no cache, no clock, no network — so this is safe
/// to call from a view body on the main thread. Whatever a rule needs ("now", the device's time
/// zone) goes in with the question.
///
/// Requests carry app models in the API wire shape (`/api/v1`), encoded exactly as they would be
/// for the server. That is the contract both sides already test; nothing is mirrored field by
/// field across the boundary.
public enum CoreRules {
    /// Ask one rule. `request` must encode a `kind` the core knows — see
    /// `astrid_core::rules::Rule`.
    public static func ask<Answer: Decodable>(
        _ request: some Encodable, as answer: Answer.Type = Answer.self
    ) throws -> Answer {
        let json = try CoreJSON.encode(request)
        return try CoreJSON.answer(runRule(request: json), as: answer)
    }
}

/// How astrid-core fails: a kind to branch on, and a message for a person or a log.
public struct CoreFailure: Error, Decodable, Equatable, CustomStringConvertible {
    public enum Kind: String, Decodable, Sendable {
        case badRequest, unauthorized, refused, offline, notFound, cache
        /// A kind this build does not know — a newer core. Treated as a refusal.
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    public let kind: Kind
    public let message: String
    /// The HTTP status, when the server gave one.
    public let status: Int?
    /// What was not found.
    public let id: String?

    public var description: String { "astrid-core \(kind.rawValue): \(message)" }
}

/// The JSON both doors speak.
///
/// Dates go out as ISO 8601 and come back in either precision: the core writes whole seconds,
/// the server writes milliseconds, and a decoder that only read one would drop the other's dates.
public enum CoreJSON {
    public static func encode(_ value: some Encodable) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    /// Unwrap the core's envelope — `{"ok":true,"value":…}` or `{"ok":false,"error":…}`.
    public static func answer<Answer: Decodable>(_ json: String, as _: Answer.Type) throws -> Answer {
        let envelope = try decoder.decode(Envelope<Answer>.self, from: Data(json.utf8))
        if let error = envelope.error { throw error }
        if let value = envelope.value { return value }
        // `{"ok":true}` with nothing in it: only an answer type that can be empty accepts that.
        if let empty = try? decoder.decode(Answer.self, from: Data("null".utf8)) { return empty }
        throw CoreFailure(kind: .badRequest, message: "the core answered with no value", status: nil, id: nil)
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.string(from: date))
        }
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = Self.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }()

    /// Milliseconds, the server's own precision: a completion stamped with whole seconds would
    /// sort ambiguously against one made in the same second.
    static func string(from date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    static func date(from text: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let without = Date.ISO8601FormatStyle()
        return (try? withFraction.parse(text)) ?? (try? without.parse(text))
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let ok: Bool
        let value: Value?
        let error: CoreFailure?
    }
}
