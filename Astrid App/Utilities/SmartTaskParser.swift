import Foundation

/// Result of parsing a task input string
struct ParsedTaskInput {
    let title: String
    let dueDateTime: Date?
    let priority: Int?
    let listIds: [String]
    let repeating: Task.Repeating?
    let customRepeatingData: CustomRepeatingPattern?
}

/// Smart task parser that extracts structured data from task title text
/// Matches the web implementation in lib/task-manager-utils.ts
struct SmartTaskParser {

    // MARK: - Pre-compiled Regex Patterns
    // These are compiled once at app startup to avoid first-use latency

    private static let hashtagRegex = try! NSRegularExpression(
        pattern: "(?:^|\\s)#([^\\s]+)",
        options: .caseInsensitive
    )

    private static let weeklyWithDayRegex = try! NSRegularExpression(
        pattern: "\\b(?:weekly|every\\s+week)\\s+((?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\\s*(?:and|,)\\s*(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))*)\\b",
        options: .caseInsensitive
    )

    private static let dailyRegex = try! NSRegularExpression(
        pattern: "\\b(daily|every\\s+day)\\b",
        options: .caseInsensitive
    )

    private static let weeklyRegex = try! NSRegularExpression(
        pattern: "\\b(weekly|every\\s+week)\\b",
        options: .caseInsensitive
    )

    private static let monthlyRegex = try! NSRegularExpression(
        pattern: "\\b(monthly|every\\s+month)\\b",
        options: .caseInsensitive
    )

    private static let yearlyRegex = try! NSRegularExpression(
        pattern: "\\b(yearly|annually|every\\s+year)\\b",
        options: .caseInsensitive
    )

    private static let todayRegex = try! NSRegularExpression(pattern: "\\btoday\\b", options: .caseInsensitive)
    private static let tomorrowRegex = try! NSRegularExpression(pattern: "\\btomorrow\\b", options: .caseInsensitive)
    private static let nextWeekRegex = try! NSRegularExpression(pattern: "\\bnext week\\b", options: .caseInsensitive)
    private static let thisWeekRegex = try! NSRegularExpression(pattern: "\\bthis week\\b", options: .caseInsensitive)
    private static let mondayRegex = try! NSRegularExpression(pattern: "\\bmonday\\b", options: .caseInsensitive)
    private static let tuesdayRegex = try! NSRegularExpression(pattern: "\\btuesday\\b", options: .caseInsensitive)
    private static let wednesdayRegex = try! NSRegularExpression(pattern: "\\bwednesday\\b", options: .caseInsensitive)
    private static let thursdayRegex = try! NSRegularExpression(pattern: "\\bthursday\\b", options: .caseInsensitive)
    private static let fridayRegex = try! NSRegularExpression(pattern: "\\bfriday\\b", options: .caseInsensitive)
    private static let saturdayRegex = try! NSRegularExpression(pattern: "\\bsaturday\\b", options: .caseInsensitive)
    private static let sundayRegex = try! NSRegularExpression(pattern: "\\bsunday\\b", options: .caseInsensitive)

    private static let highestPriorityRegex = try! NSRegularExpression(pattern: "\\b(highest priority|urgent|asap)\\b", options: .caseInsensitive)
    private static let highPriorityRegex = try! NSRegularExpression(pattern: "\\bhigh priority\\b", options: .caseInsensitive)
    private static let mediumPriorityRegex = try! NSRegularExpression(pattern: "\\bmedium priority\\b", options: .caseInsensitive)
    private static let lowPriorityRegex = try! NSRegularExpression(pattern: "\\b(low priority|lowest priority)\\b", options: .caseInsensitive)

    /// Call during app startup to ensure all regex patterns are compiled
    /// This moves compilation from first-use to app init
    static func warmUp() {
        // Touch all static regex properties to trigger lazy initialization
        _ = hashtagRegex
        _ = weeklyWithDayRegex
        _ = dailyRegex
        _ = weeklyRegex
        _ = monthlyRegex
        _ = yearlyRegex
        _ = todayRegex
        _ = tomorrowRegex
        _ = nextWeekRegex
        _ = thisWeekRegex
        _ = mondayRegex
        _ = tuesdayRegex
        _ = wednesdayRegex
        _ = thursdayRegex
        _ = fridayRegex
        _ = saturdayRegex
        _ = sundayRegex
        _ = highestPriorityRegex
        _ = highPriorityRegex
        _ = mediumPriorityRegex
        _ = lowPriorityRegex
        AppLog.debug("⚡️ [SmartTaskParser] Regex patterns pre-compiled")
    }

    /// Parse task input string to extract structured task data
    /// - Parameters:
    ///   - input: The raw task title input
    ///   - lists: Available lists for hashtag matching
    /// - Returns: ParsedTaskInput with extracted metadata
    static func parse(_ input: String, lists: [TaskList] = []) -> ParsedTaskInput {
        var title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var dueDateTime: Date? = nil
        var priority: Int? = nil
        var extractedListIds: [String] = []
        var repeating: Task.Repeating? = nil
        var customRepeatingData: CustomRepeatingPattern? = nil

        // Parse hashtags for list assignment
        // Match hashtags like #shopping, #work, etc.
        do {
            let range = NSRange(title.startIndex..., in: title)
            let matches = Self.hashtagRegex.matches(in: title, options: [], range: range)

            // Get real lists (non-virtual)
            let realLists = lists.filter { $0.isVirtual != true }

            for match in matches {
                if let hashtagRange = Range(match.range(at: 1), in: title) {
                    let hashtagName = String(title[hashtagRange]).lowercased()

                    // Find matching list by name (case-insensitive, fuzzy match)
                    let matchingList = realLists.first { list in
                        let listNameLower = list.name.lowercased()
                        return listNameLower.replacingOccurrences(of: " ", with: "-") == hashtagName ||
                               listNameLower.replacingOccurrences(of: " ", with: "_") == hashtagName ||
                               listNameLower.replacingOccurrences(of: " ", with: "") == hashtagName ||
                               listNameLower == hashtagName
                    }

                    if let matchingList = matchingList, !extractedListIds.contains(matchingList.id) {
                        extractedListIds.append(matchingList.id)
                    }
                }
            }

            // Remove all hashtags from title
            title = Self.hashtagRegex.stringByReplacingMatches(
                in: title,
                options: [],
                range: range,
                withTemplate: " "
            )
            title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Parse repeating patterns BEFORE date keywords
        // This allows "weekly Monday" to be parsed as "repeat weekly on Monday"

        // Pattern: "weekly [day]" or "every week [day]" - weekly repeating on specific day(s)
        do {
            let range = NSRange(title.startIndex..., in: title)
            if let match = Self.weeklyWithDayRegex.firstMatch(in: title, options: [], range: range),
               let daysRange = Range(match.range(at: 1), in: title) {
                // Extract weekdays from the match
                let daysString = String(title[daysRange]).lowercased()
                let dayNames = daysString
                    .components(separatedBy: CharacterSet(charactersIn: ","))
                    .flatMap { $0.components(separatedBy: " and ") }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                // Set up custom weekly repeating pattern
                repeating = .custom
                customRepeatingData = CustomRepeatingPattern(
                    type: "custom",
                    unit: "weeks",
                    interval: 1,
                    endCondition: "never",
                    weekdays: dayNames
                )

                // Set due date to next occurrence of first day
                if let firstDay = dayNames.first {
                    dueDateTime = Self.getNextWeekdayByName(firstDay)
                }

                // Remove the entire "weekly [day]" phrase from title
                title = Self.weeklyWithDayRegex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
                title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Pattern: Simple repeating keywords (daily, weekly, monthly, yearly, annually)
        // Only parse if we haven't already matched a more specific pattern above
        if repeating == nil {
            let simpleRepeatingPatterns: [(regex: NSRegularExpression, value: Task.Repeating)] = [
                (Self.dailyRegex, .daily),
                (Self.weeklyRegex, .weekly),
                (Self.monthlyRegex, .monthly),
                (Self.yearlyRegex, .yearly)
            ]

            for (regex, value) in simpleRepeatingPatterns {
                let range = NSRange(title.startIndex..., in: title)
                if regex.firstMatch(in: title, options: [], range: range) != nil {
                    repeating = value
                    title = regex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
                    title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        // Parse date keywords
        // Skip if we already set a date from the repeating pattern (e.g., "weekly Monday")
        let datePatterns: [(regex: NSRegularExpression, handler: () -> Date?)] = [
            (Self.todayRegex, { Calendar.current.startOfDay(for: Date()) }),
            (Self.tomorrowRegex, { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) }),
            (Self.nextWeekRegex, { Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) }),
            (Self.thisWeekRegex, { Self.getEndOfWeek() }),
            (Self.mondayRegex, { Self.getNextWeekday(2) }),
            (Self.tuesdayRegex, { Self.getNextWeekday(3) }),
            (Self.wednesdayRegex, { Self.getNextWeekday(4) }),
            (Self.thursdayRegex, { Self.getNextWeekday(5) }),
            (Self.fridayRegex, { Self.getNextWeekday(6) }),
            (Self.saturdayRegex, { Self.getNextWeekday(7) }),
            (Self.sundayRegex, { Self.getNextWeekday(1) })
        ]

        for (regex, handler) in datePatterns {
            let range = NSRange(title.startIndex..., in: title)
            if regex.firstMatch(in: title, options: [], range: range) != nil {
                // Only set date if we haven't already set one from repeating pattern
                if dueDateTime == nil {
                    dueDateTime = handler()
                }
                // Always remove the date keyword from title
                title = regex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
                title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Parse priority keywords
        let priorityPatterns: [(regex: NSRegularExpression, value: Int)] = [
            (Self.highestPriorityRegex, 3),
            (Self.highPriorityRegex, 2),
            (Self.mediumPriorityRegex, 1),
            (Self.lowPriorityRegex, 0)
        ]

        for (regex, value) in priorityPatterns {
            let range = NSRange(title.startIndex..., in: title)
            if regex.firstMatch(in: title, options: [], range: range) != nil {
                priority = value
                title = regex.stringByReplacingMatches(in: title, options: [], range: range, withTemplate: "")
                title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Fallback to original if title becomes empty
        if title.isEmpty {
            title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParsedTaskInput(
            title: title,
            dueDateTime: dueDateTime,
            priority: priority,
            listIds: extractedListIds,
            repeating: repeating,
            customRepeatingData: customRepeatingData
        )
    }

    // MARK: - Private Helpers

    /// Get the next occurrence of a weekday by name
    /// - Parameter weekdayName: Lowercase weekday name (e.g., "monday", "tuesday")
    private static func getNextWeekdayByName(_ weekdayName: String) -> Date? {
        let weekdayMap: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ]
        guard let weekday = weekdayMap[weekdayName.lowercased()] else { return nil }
        return getNextWeekday(weekday)
    }

    /// Get the end of the current week (Friday at midnight)
    private static func getEndOfWeek() -> Date? {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)

        // Calculate days until Friday (weekday 6)
        var daysUntilFriday = 6 - weekday
        if daysUntilFriday < 0 {
            daysUntilFriday += 7
        }

        return calendar.date(byAdding: .day, value: daysUntilFriday, to: calendar.startOfDay(for: today))
    }

    /// Get the next occurrence of a weekday
    /// - Parameter weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    private static func getNextWeekday(_ weekday: Int) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentWeekday = calendar.component(.weekday, from: today)

        var daysToAdd = weekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: today)
    }
}
