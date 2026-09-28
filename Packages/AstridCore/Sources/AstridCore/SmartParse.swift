import Foundation

/// What a quick-add line says — astrid-core's `parse::smart`, the web's `parseTaskInput` in every
/// language the apps ship.
public struct SmartParse: Decodable, Equatable, Sendable {
    /// The line with every recognised word and every `#tag` taken out.
    public let title: String
    /// The lists its `#tags` named, in the order they were typed.
    public let listIds: [String]
    /// The day a date word named, as a calendar date — `nil` when it named none. An all-day date:
    /// store it at UTC midnight, like every other all-day date.
    public let dueDay: DateComponents?
    /// 0 (low) through 3 (urgent), when a priority word was typed.
    public let priority: Int?
    /// `daily`, `weekly`, `monthly`, `yearly`, or `custom` with `weekdays`.
    public let repeating: String?
    /// For a `custom` weekly repeat: the days, as the wire names them (`monday`).
    public let weekdays: [String]

    private enum Keys: String, CodingKey { case title, listIds, dueDay, priority, repeating, weekdays }

    public init(from decoder: Decoder) throws {
        let parsed = try decoder.container(keyedBy: Keys.self)
        title = try parsed.decode(String.self, forKey: .title)
        listIds = try parsed.decode([String].self, forKey: .listIds)
        priority = try parsed.decodeIfPresent(Int.self, forKey: .priority)
        repeating = try parsed.decodeIfPresent(String.self, forKey: .repeating)
        weekdays = try parsed.decode([String].self, forKey: .weekdays)
        dueDay = try parsed.decodeIfPresent(String.self, forKey: .dueDay).flatMap(Self.day)
    }

    /// `2026-09-29` as its parts, with no time and no zone — a day, not a moment.
    private static func day(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}

/// A list a `#tag` may name: the four fields the rule reads.
public struct SmartParseList: Encodable, Sendable {
    public let id: String
    public let name: String
    public let isVirtual: Bool?
    public let listType: String?

    public init(id: String, name: String, isVirtual: Bool?, listType: String?) {
        self.id = id
        self.name = name
        self.isVirtual = isVirtual
        self.listType = listType
    }
}

extension CoreRules {
    /// Parse a quick-add line. `today` is the person's calendar day; `locale` the app's language.
    /// Never throws: a line the core cannot read is a title and nothing else.
    public static func smartParse(
        _ text: String, lists: [SmartParseList], locale: String, today: DateComponents
    ) -> SmartParse? {
        guard let year = today.year, let month = today.month, let day = today.day else { return nil }
        return try? ask(
            SmartParseRequest(
                text: text, lists: lists, locale: locale,
                today: String(format: "%04d-%02d-%02d", year, month, day)),
            as: SmartParse.self)
    }
}

private struct SmartParseRequest: Encodable {
    let kind = "smartParse"
    let text: String
    let lists: [SmartParseList]
    let locale: String
    let today: String
}
