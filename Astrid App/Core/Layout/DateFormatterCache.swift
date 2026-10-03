//  DateFormatterCache.swift
//  One DateFormatter per format and time zone, not one per row per redraw (AITD-455).
//
//  Building a DateFormatter is expensive — it loads ICU locale data — and a task row built two or
//  three on every body evaluation. Formatting with a shared one is thread-safe.
//
//  A cached formatter keeps the locale it was made with, including the 12/24-hour choice, so the
//  cache empties when the locale or the system time zone changes. The zone is part of the key
//  because all-day dates are read in UTC and timed ones in the user's zone (see DueDateLabel).

import Foundation

nonisolated enum DateFormatterCache {

    enum Spec: Hashable {
        /// A localized template — field order follows the locale.
        case template(String)
        /// A literal pattern, used as written.
        case pattern(String)
        case styles(date: DateFormatter.Style, time: DateFormatter.Style)
    }

    /// `timeZone: nil` means the user's own zone.
    static func formatter(_ spec: Spec, timeZone: TimeZone? = nil) -> DateFormatter {
        storage.formatter(spec, timeZone: timeZone ?? .current)
    }

    /// Gregorian in UTC — how an all-day date is stored and must be read.
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let storage = Storage()

    private final class Storage: @unchecked Sendable {
        private struct Key: Hashable {
            let spec: Spec
            let timeZone: String
        }

        private let lock = NSLock()
        private var formatters: [Key: DateFormatter] = [:]
        private var observers: [NSObjectProtocol] = []

        init() {
            let center = NotificationCenter.default
            for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
                observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.removeAll()
                })
            }
        }

        func formatter(_ spec: Spec, timeZone: TimeZone) -> DateFormatter {
            let key = Key(spec: spec, timeZone: timeZone.identifier)
            lock.lock()
            defer { lock.unlock() }
            if let cached = formatters[key] { return cached }

            let formatter = DateFormatter()
            switch spec {
            case .template(let template): formatter.setLocalizedDateFormatFromTemplate(template)
            case .pattern(let pattern): formatter.dateFormat = pattern
            case .styles(let date, let time):
                formatter.dateStyle = date
                formatter.timeStyle = time
            }
            formatter.timeZone = timeZone
            formatters[key] = formatter
            return formatter
        }

        private func removeAll() {
            lock.lock()
            formatters.removeAll()
            lock.unlock()
        }
    }
}
