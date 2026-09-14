//  WireDate.swift
//  The one date format the app WRITES to the Astrid API.
//
//  `ISO8601DateFormatter()` out of the box is `.withInternetDateTime` and nothing else — no
//  fractional seconds — so every timestamp built with a bare instance is silently truncated to
//  the whole second. For a due date that is harmless. For `completedAt` it was not: it is an
//  audit field, and four completions on 2026-09-08T14:02:37 landed on the server as four
//  identical `…:37.000Z` stamps, indistinguishable and unorderable (AITD-369). The investigation
//  into what wrote them stalled on exactly that missing precision.
//
//  Reading was never the problem FOR THE DECODER — `AstridAPIClient`'s tries fractional seconds
//  first and falls back. But hand-rolled parses elsewhere did not, and a bare formatter does not
//  merely lose precision on the way in: it returns nil for any string carrying milliseconds. Now
//  that we deliberately WRITE `.869Z` stamps, those sites silently dropped the date rather than
//  truncating it — a list's default due date simply not applying. Hence `date(from:)` (AITD-404).

import Foundation

enum WireDate {

    /// RFC3339 with milliseconds: `2026-09-08T14:02:37.869Z`.
    ///
    /// A stored formatter rather than a fresh one per call. `ISO8601DateFormatter` is expensive
    /// to build and this sits on the completion path, which is the hottest write in the app.
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Whole seconds: `2026-09-08T14:02:37Z`. Also stored — the due-date paths built a fresh
    /// `ISO8601DateFormatter()` per call, and that type is expensive to construct.
    private static let secondsFormatter = ISO8601DateFormatter()

    /// Format an instant for the wire, keeping the milliseconds.
    ///
    /// Use this for any timestamp whose ORDER matters — anything two of which could be written
    /// inside one second and later need telling apart.
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Format a DUE DATE for the wire — deliberately without milliseconds (AITD-404).
    ///
    /// A due date is a whole minute, or UTC midnight for an all-day task. Nothing orders two of
    /// them by sub-second precision, so adding `.000` would change what goes on the wire for a
    /// field that gains nothing by it. This exists for the OTHER half of the problem: the due-date
    /// paths in `TaskService`, `TaskDetailViewNew` and `AstridAPIClient` each allocated a fresh
    /// formatter per call, on the task-write path.
    static func dueDateString(from date: Date) -> String {
        secondsFormatter.string(from: date)
    }

    /// Parse a timestamp the server sent, whether or not it carries milliseconds.
    ///
    /// FRACTIONAL FIRST, THEN PLAIN — the same rule `AstridAPIClient`'s decoder uses, because a
    /// formatter configured for one shape returns nil for the other rather than coping. Both
    /// mistakes were live: bare parsers rejected `.869Z`, and `AccountSettingsView` set
    /// `.withFractionalSeconds` only and so rejected `…:37Z`.
    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? secondsFormatter.date(from: string)
    }
}
