import Foundation

/// One command for the client door — `astrid_core::app::Command` — as a `kind` and its fields.
///
/// A field is either a value or an explicit `null`; a field that is not set at all is absent from
/// the JSON. The difference matters: in an edit, `null` clears ("remove the due date") and absent
/// leaves alone, and a type that could not tell them apart would make one of them impossible.
public struct CoreCommand: Encodable, Sendable {
    public let kind: String
    public private(set) var fields: [String: CoreValue]

    public init(kind: String, _ fields: [String: CoreValue] = [:]) {
        self.kind = kind
        self.fields = fields
    }

    /// Set a field when there is something to set; leave it absent otherwise.
    public mutating func set(_ key: String, _ value: (some Encodable & Sendable)?) {
        if let value { fields[key] = .value(value) }
    }

    /// Send the field as `null`: in an edit, clear it.
    public mutating func clear(_ key: String) {
        fields[key] = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FieldKey.self)
        try container.encode(kind, forKey: FieldKey("kind"))
        for (key, value) in fields {
            switch value {
            case .null: try container.encodeNil(forKey: FieldKey(key))
            case .value(let encodable): try container.encode(AnyEncodable(encodable), forKey: FieldKey(key))
            }
        }
    }
}

/// A field's value: something, or an explicit `null`.
public enum CoreValue: Sendable {
    case null
    case value(any Encodable & Sendable)

    /// A nested object of fields — an edit's `changes`.
    public static func object(_ fields: [String: CoreValue]) -> CoreValue {
        .value(CoreFields(fields: fields))
    }
}

/// A bare object of fields, encoded the way `CoreCommand` encodes its own.
public struct CoreFields: Encodable, Sendable {
    public var fields: [String: CoreValue]

    public init(fields: [String: CoreValue] = [:]) {
        self.fields = fields
    }

    public mutating func set(_ key: String, _ value: (some Encodable & Sendable)?) {
        if let value { fields[key] = .value(value) }
    }

    public mutating func clear(_ key: String) {
        fields[key] = .null
    }

    public var isEmpty: Bool { fields.isEmpty }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FieldKey.self)
        for (key, value) in fields {
            switch value {
            case .null: try container.encodeNil(forKey: FieldKey(key))
            case .value(let encodable): try container.encode(AnyEncodable(encodable), forKey: FieldKey(key))
            }
        }
    }
}

struct FieldKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
