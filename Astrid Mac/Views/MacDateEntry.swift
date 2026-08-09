//  MacDateEntry.swift
//  Astrid for Mac — typing a date.
//
//  The popover has been through two failed attempts at this. `.field` gives a
//  typable control but brings the system's own small calendar overlay, so two
//  calendars appeared at once. `.graphical` gives a calendar we can size and
//  centre, but no way to type at all — which is what is being reported now.
//
//  So the typing is ours: a plain text field, parsed here. That decouples "can
//  the user type a date" from whatever NSDatePicker decides to render, and makes
//  the parsing testable rather than hoped for.

#if os(macOS)
import Foundation

enum MacDateEntry {

    /// How a date is shown in the field: the user's own short format, so it
    /// matches what they will type.
    static func format(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Parse what the user typed, or nil.
    ///
    /// Tries the locale's own short and medium forms first — someone typing a
    /// date types it the way their system shows it — then a couple of tolerant
    /// numeric fallbacks, because "8/12/26" and "8/12/2026" are both things
    /// people type and neither should be rejected.
    ///
    /// Returns nil rather than guessing when nothing matches: a wrong date
    /// silently accepted is worse than a field that declines to change.
    static func parse(_ text: String, locale: Locale = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for style in [DateFormatter.Style.short, .medium, .long] {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = style
            formatter.timeStyle = .none
            if let date = formatter.date(from: trimmed) { return date }
        }

        // Numeric fallbacks in the locale's own field order.
        for template in ["yMd", "yMMMd"] {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}
#endif
