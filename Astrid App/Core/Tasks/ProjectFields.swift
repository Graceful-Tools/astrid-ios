//  ProjectFields.swift
//  A GitHub board's project fields in task details (AITD-491; web AWTD-1210,
//  `TaskProjectFieldsSection.tsx`). Shared by the iOS rows and the Mac's.
//
//  Which fields show, in what order, and how an iteration's choices sort are astrid-core's
//  (`services::project_fields`, CONTRACTS D56) — the rules web `lib/project-field-display.ts`
//  states. This file is the wire shape, the words a value is drawn with, and the service.

import AstridCore
import Foundation

/// One value: an option or iteration id, a `YYYY-MM-DD` day or text are strings; a number is one.
nonisolated enum ProjectFieldValue: Codable, Equatable, Hashable {
    case text(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        }
    }

    var text: String? { if case .text(let text) = self { return text } else { return nil } }
    var number: Double? { if case .number(let number) = self { return number } else { return nil } }
}

nonisolated struct ProjectFieldOption: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let color: String?
}

nonisolated struct ProjectFieldIteration: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let title: String
    let startDate: String
    let duration: Int
    /// Over — current and upcoming come first, and a completed one is kept so a task still on it
    /// draws its title rather than an id.
    let completed: Bool
}

/// One row: a field and this task's value for it (`nil` is no value).
nonisolated struct ProjectFieldRow: Codable, Equatable, Identifiable {
    enum Kind: String { case text, number, date, singleSelect = "single_select", iteration }

    let id: String
    let name: String
    let dataType: String
    let options: [ProjectFieldOption]
    let iterations: [ProjectFieldIteration]
    let value: ProjectFieldValue?

    /// The core only sends the five it has editors for; `nil` would be a newer core's type.
    var kind: Kind? { Kind(rawValue: dataType) }

    /// The words the row shows for its value, or `nil` for none — an option's or iteration's
    /// name rather than its id, a day in the reader's own format.
    func displayText(locale: Locale = .current) -> String? {
        guard let value else { return nil }
        switch kind {
        case .singleSelect:
            return options.first { $0.id == value.text }?.name ?? value.text
        case .iteration:
            return iterations.first { $0.id == value.text }?.title ?? value.text
        case .date:
            guard let text = value.text, let day = ProjectFieldRow.day(from: text) else { return value.text }
            var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
            style.timeZone = TimeZone(identifier: "UTC")!
            return day.formatted(style)
        case .number:
            return value.number.map { $0.formatted(.number.locale(locale)) } ?? value.text
        case .text, .none:
            return value.text ?? value.number.map { $0.formatted(.number.locale(locale)) }
        }
    }

    /// What a text or number editor starts from: the value as typed, no grouping separators.
    var editableText: String {
        switch value {
        case .number(let number): return number.formatted(.number.grouping(.never))
        case .text(let text): return text
        case nil: return ""
        }
    }

    /// A date picker draws in local time and GitHub's day is midnight UTC: the same calendar day,
    /// here, so the picker never shows the day before.
    static func localDay(_ utcMidnight: Date, in calendar: Calendar = .current) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day], from: utcMidnight)
        return calendar.date(from: parts) ?? utcMidnight
    }

    /// `YYYY-MM-DD` as midnight UTC, the day GitHub means — and back, for the date editor.
    static func day(from text: String) -> Date? {
        dayFormatter.date(from: text)
    }

    static func dayText(from date: Date, in calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// What task details draw. No rows for a task off a GitHub board, so a classic task is unchanged.
nonisolated struct TaskProjectFields: Codable, Equatable {
    let projectId: String?
    let rows: [ProjectFieldRow]

    static let none = TaskProjectFields(projectId: nil, rows: [])
}

nonisolated enum ProjectFieldErrors {
    /// The `Localizable.strings` key for a failed save: the two GitHub problems a person can act
    /// on get their own words, as on web; everything else is one message rather than a code.
    static func messageKey(for error: Error) -> String {
        let code = (error as? CoreFailure)?.message ?? ""
        if code.contains("sso_required") { return "tasks.projectFields.errorSsoRequired" }
        if code.contains("auth_required") { return "tasks.projectFields.errorAuthRequired" }
        return "tasks.projectFields.errorSaveFailed"
    }
}

/// The Canonical Control Point for project fields: views ask this, never an API client
/// (ASTRID.md §0 rule 1). An edit is sent at once and a refusal thrown; only when the network
/// failed does the core queue it (astrid-core CONTRACTS D56).
@MainActor
final class ProjectFieldService {
    static let shared = ProjectFieldService()

    private var core: CoreSession { AppCore.shared.session }

    /// The rows for a task — the server's, or the cache's when offline.
    func fields(taskId: String) async throws -> TaskProjectFields {
        try await core.run(CoreCommand(kind: "taskProjectFields", taskId: taskId), as: TaskProjectFields.self)
    }

    /// Set one field, or clear it with `nil`. Answers with the rows after the edit.
    func set(taskId: String, fieldId: String, value: ProjectFieldValue?) async throws -> TaskProjectFields {
        var command = CoreCommand(kind: "setTaskProjectField", ["taskId": .value(taskId), "fieldId": .value(fieldId)])
        command.set("value", value)  // `nil` leaves the key out, which the core reads as a clear

        return try await core.run(command, as: TaskProjectFields.self)
    }
}
