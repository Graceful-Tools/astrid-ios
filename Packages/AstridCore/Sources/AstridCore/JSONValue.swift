import Foundation

/// Any JSON value, for forwarding a shape the core reads but the caller does not model.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let bool = try? container.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? container.decode(Double.self) { self = .number(number) }
        else if let string = try? container.decode(String.self) { self = .string(string) }
        else if let array = try? container.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers go out as integers: the core reads a priority or a duration as one.
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int64(value)) }
            else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// `value` as the JSON its own `Encodable` writes, through the core's encoder (so dates are ISO
    /// 8601, as the wire wants).
    public init(encoding value: some Encodable) throws {
        let data = Data(try CoreJSON.encode(value).utf8)
        self = try CoreJSON.decoder.decode(JSONValue.self, from: data)
    }
}

extension CoreFields {
    /// Every field `request` writes, as it writes it — `null` included.
    public init(encoding request: some Encodable) throws {
        guard case .object(let object) = try JSONValue(encoding: request) else {
            self.init()
            return
        }
        self.init(fields: object.mapValues { $0 == .null ? .null : .value($0) })
    }
}
