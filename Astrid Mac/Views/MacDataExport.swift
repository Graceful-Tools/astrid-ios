//  MacDataExport.swift
//  Astrid for Mac — pure helpers for the account data export (Task 180199c0).

#if os(macOS)
import Foundation
import UniformTypeIdentifiers

enum MacDataExport {
    /// Suggested export filename, e.g. "astrid-export-2026-07-18.json".
    static func fileName(format: String, date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "astrid-export-\(stamp).\(format)"
    }

    /// UTType for the save panel by format.
    static func contentType(format: String) -> UTType {
        format == "csv" ? .commaSeparatedText : .json
    }
}
#endif
