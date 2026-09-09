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
//  Reading was never the problem — `AstridAPIClient`'s decoder tries fractional seconds first
//  and falls back — so this is about what goes OUT.

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

    /// Format an instant for the wire, keeping the milliseconds.
    ///
    /// Use this for any timestamp whose ORDER matters — anything two of which could be written
    /// inside one second and later need telling apart.
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
