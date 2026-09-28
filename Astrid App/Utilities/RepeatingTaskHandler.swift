import AstridCore
import Foundation

/// Next-occurrence math for repeating tasks — **answered by astrid-core**.
///
/// The math lives in one place for every client: `astrid_core::repeating`
/// (https://github.com/Graceful-Tools/astrid-core), locked against astrid-web by the contract
/// fixtures there. This type is the Swift face of it and holds no pattern logic of its own; the
/// Swift copy it replaced had drifted from the web (astrid-core `docs/CONTRACTS.md` D1, D5).
///
/// ⚠️ Do NOT add pattern math anywhere in the app. A change to how a series rolls is a change to
/// the web first, then astrid-core, then a bump of the core these apps pin. Production completes
/// through `TaskService.completeTask`, which asks `CoreRules.completion` for the whole outcome;
/// this calculator is the same answer one level down, for the places that want just the date.

/// End condition data that can be used with simple repeating patterns
struct SimplePatternEndCondition {
    var endCondition: String  // "never", "after_occurrences", "until_date"
    var endAfterOccurrences: Int?
    var endUntilDate: Date?
}

enum RepeatingTaskCalculator {
    typealias Result = (nextDueDate: Date?, shouldTerminate: Bool, newOccurrenceCount: Int)

    /// Next occurrence for a simple pattern (daily, weekly, monthly, yearly), optionally carrying
    /// an end condition.
    static func calculateSimpleNextOccurrence(
        repeatingType: Task.Repeating,
        currentDueDate: Date?,
        completionDate: Date,
        repeatFrom: Task.RepeatFromMode,
        currentOccurrenceCount: Int = 0,
        endData: SimplePatternEndCondition? = nil,
        isAllDay: Bool = false
    ) -> Result {
        let endPattern = endData.map {
            CustomRepeatingPattern(
                endCondition: $0.endCondition, endAfterOccurrences: $0.endAfterOccurrences,
                endUntilDate: $0.endUntilDate)
        }
        return ask(
            repeating: repeatingType.rawValue, pattern: endPattern, currentDueDate: currentDueDate,
            completionDate: completionDate, repeatFrom: repeatFrom, occurrenceCount: currentOccurrenceCount,
            isAllDay: isAllDay)
    }

    /// Next occurrence for a custom pattern: weekdays, monthly same date or same weekday, yearly.
    static func calculateCustomNextOccurrence(
        pattern: CustomRepeatingPattern,
        currentDueDate: Date?,
        completionDate: Date,
        repeatFrom: Task.RepeatFromMode,
        currentOccurrenceCount: Int,
        isAllDay: Bool = false
    ) -> Result {
        ask(
            repeating: Task.Repeating.custom.rawValue, pattern: pattern, currentDueDate: currentDueDate,
            completionDate: completionDate, repeatFrom: repeatFrom, occurrenceCount: currentOccurrenceCount,
            isAllDay: isAllDay)
    }

    private static func ask(
        repeating: String, pattern: CustomRepeatingPattern?, currentDueDate: Date?,
        completionDate: Date, repeatFrom: Task.RepeatFromMode, occurrenceCount: Int, isAllDay: Bool
    ) -> Result {
        let request = NextOccurrenceRequest(
            repeating: repeating, pattern: pattern, currentDueDate: currentDueDate,
            completion: completionDate, repeatFrom: repeatFrom.rawValue, occurrenceCount: occurrenceCount,
            timeZone: TimeZone.current.identifier, isAllDay: isAllDay)
        do {
            let answer = try CoreRules.ask(request, as: NextOccurrenceAnswer.self)
            return (answer.nextDueDate, answer.shouldTerminate, answer.newOccurrenceCount)
        } catch {
            // The core answers every well-formed request; a failure here is a bug in this request.
            // Holding the series where it is is the least surprising thing to show meanwhile.
            AppLog.debug("⚠️ [RepeatingTaskCalculator] astrid-core refused nextOccurrence: \(error)")
            return (nil, false, occurrenceCount)
        }
    }

    private struct NextOccurrenceRequest: Encodable {
        let kind = "nextOccurrence"
        let repeating: String
        let pattern: CustomRepeatingPattern?
        let currentDueDate: Date?
        let completion: Date
        let repeatFrom: String
        let occurrenceCount: Int
        /// The calendar the steps are taken on — the device's, as this calculator always used.
        let timeZone: String
        /// An all-day series steps on UTC midnights, where its dates live, whatever the zone.
        let isAllDay: Bool
    }

    private struct NextOccurrenceAnswer: Decodable {
        let nextDueDate: Date?
        let shouldTerminate: Bool
        let newOccurrenceCount: Int
    }
}
