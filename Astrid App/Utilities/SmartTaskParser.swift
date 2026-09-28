import AstridCore
import Foundation

/// Result of parsing a task input string
struct ParsedTaskInput {
    let title: String
    /// The day a date word named, as an all-day date: UTC midnight of that day, as every all-day
    /// date is stored.
    let dueDateTime: Date?
    let priority: Int?
    let listIds: [String]
    let repeating: Task.Repeating?
    let customRepeatingData: CustomRepeatingPattern?
}

/// Smart task parsing — **answered by astrid-core** (`parse::smart`), which runs the web's
/// `parseTaskInput` (lib/task-manager-utils.ts) in every language the app ships, locked by the
/// contract fixture generated from the web.
///
/// The Swift copy it replaced was English-only and returned a date word as LOCAL midnight, which
/// the server then read as the previous day for anyone east of UTC — "tomorrow" typed in Paris
/// was today (astrid-core `docs/CONTRACTS.md` D12). A date word is a calendar day, and it is
/// stored the way every all-day date is: UTC midnight.
enum SmartTaskParser {
    /// Load the core's keyword tables before the first quick-add needs them: they are read once,
    /// on first use, and a person typing should not wait for that.
    static func warmUp() {
        _ = parse("warm up tomorrow")
    }

    /// Parse task input string to extract structured task data
    /// - Parameters:
    ///   - input: The raw task title input
    ///   - lists: Available lists for hashtag matching
    ///   - today: The person's "today"; `Date()` outside tests.
    static func parse(_ input: String, lists: [TaskList] = [], today: Date = Date()) -> ParsedTaskInput {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = CoreRules.smartParse(
            trimmed,
            lists: lists.map {
                SmartParseList(id: $0.id, name: $0.name, isVirtual: $0.isVirtual, listType: $0.listType)
            },
            locale: Bundle.main.preferredLocalizations.first ?? "en",
            today: Calendar.current.dateComponents([.year, .month, .day], from: today))
        else {
            return ParsedTaskInput(title: trimmed, dueDateTime: nil, priority: nil, listIds: [],
                                   repeating: nil, customRepeatingData: nil)
        }

        let repeating = parsed.repeating.flatMap(Task.Repeating.init(rawValue:))
        return ParsedTaskInput(
            title: parsed.title,
            dueDateTime: parsed.dueDay.flatMap(Self.utcMidnight),
            priority: parsed.priority,
            listIds: parsed.listIds,
            repeating: repeating,
            customRepeatingData: repeating == .custom
                ? CustomRepeatingPattern(type: "custom", unit: "weeks", interval: 1,
                                         endCondition: "never", weekdays: parsed.weekdays)
                : nil)
    }

    private static func utcMidnight(_ day: DateComponents) -> Date? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: day)
    }
}
