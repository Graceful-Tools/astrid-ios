import Foundation

/// Swift port of `lib/recently-completed-presets.ts` from astrid-web.
/// Drives the list-admin "Recently completed window" Picker. Keeping
/// the preset list + lookup helpers in lockstep means the iOS UI shows
/// the same options in the same order as the web UI.

enum RecentlyCompletedPresetId: String, CaseIterable {
    case default24h = "default-24h"
    case last7Days = "last-7-days"
    case last14Days = "last-14-days"
    case last28Days = "last-28-days"
    case last30Days = "last-30-days"
    case sinceLastSunday = "since-last-sunday"
    case sinceLastMonday = "since-last-monday"
    case sinceFirstOfMonth = "since-first-of-month"
    case sinceSpecificDate = "since-specific-date"
}

struct RecentlyCompletedPreset: Equatable {
    let id: RecentlyCompletedPresetId
    let label: String
    /// `nil` = legacy 24h default. The `sinceSpecificDate` preset also
    /// stores `nil` here because the date is collected via a separate
    /// picker.
    let window: RecentlyCompletedWindow?
}

let RECENTLY_COMPLETED_PRESETS: [RecentlyCompletedPreset] = [
    .init(id: .default24h,          label: "Last 24 hours (default)",          window: nil),
    .init(id: .last7Days,           label: "Last 7 days",                       window: .duration(amount: 7, unit: .day)),
    .init(id: .last14Days,          label: "Last 14 days",                      window: .duration(amount: 14, unit: .day)),
    .init(id: .last28Days,          label: "Last 28 days",                      window: .duration(amount: 28, unit: .day)),
    .init(id: .last30Days,          label: "Last 30 days",                      window: .duration(amount: 30, unit: .day)),
    .init(id: .sinceLastSunday,     label: "Since last Sunday (this week)",     window: .sinceWeekday(weekday: 0)),
    .init(id: .sinceLastMonday,     label: "Since last Monday (this week)",     window: .sinceWeekday(weekday: 1)),
    .init(id: .sinceFirstOfMonth,   label: "Since the 1st of the month",        window: .sinceDayOfMonth(day: 1)),
    .init(id: .sinceSpecificDate,   label: "Since a specific date…",            window: nil),
]

/// Find the preset that matches a stored window. Returns the default
/// preset when window is nil. Returns `.sinceSpecificDate` for any
/// since-date window (the date itself is shown separately in the UI).
func findPresetForWindow(_ window: RecentlyCompletedWindow?) -> RecentlyCompletedPreset? {
    guard let window = window else {
        return RECENTLY_COMPLETED_PRESETS.first { $0.id == .default24h }
    }
    switch window {
    case .sinceDate:
        return RECENTLY_COMPLETED_PRESETS.first { $0.id == .sinceSpecificDate }
    case .duration, .sinceWeekday, .sinceDayOfMonth:
        return RECENTLY_COMPLETED_PRESETS.first { preset in
            guard let presetWindow = preset.window else { return false }
            return presetWindow == window
        }
    }
}

/// Inverse mapping: preset id → window value to persist. For
/// `default24h` and `sinceSpecificDate` returns nil (the caller stores
/// the legacy default or prompts for a date and persists the constructed
/// window itself).
func presetForValue(_ id: RecentlyCompletedPresetId) -> RecentlyCompletedWindow? {
    if id == .default24h || id == .sinceSpecificDate { return nil }
    return RECENTLY_COMPLETED_PRESETS.first { $0.id == id }?.window
}

/// Pure helper that applies a list's completion filter to a task array,
/// honoring the list's per-list `recentlyCompletedWindow`. Mirrors the
/// web's `shouldShowCompletedByFilter` wiring in `hooks/useFilterState.ts`.
///
/// - Parameters:
///   - tasks: candidates
///   - filter: "all" | "completed" | "incomplete" | "default" (default
///     is "default" — show incomplete + tasks completed inside the
///     window)
///   - window: the list's per-list recently-completed window; nil falls
///     back to the legacy 24-hour default
///   - now: injectable clock for tests
func applyCompletionFilterWithWindow(
    _ tasks: [Task],
    filter: String,
    window: RecentlyCompletedWindow?,
    now: Date = Date()
) -> [Task] {
    switch filter {
    case "all":
        return tasks
    case "completed":
        return tasks.filter { $0.completed }
    case "incomplete":
        return tasks.filter { !$0.completed }
    case "default":
        return tasks.filter { task in
            shouldShowCompletedByFilter(
                filterMode: task.completed ? "default" : "show",
                completedAt: task.completedAt ?? task.updatedAt,
                updatedAt: task.updatedAt,
                window: window,
                now: now
            )
        }
    default:
        return applyCompletionFilterWithWindow(tasks, filter: "default", window: window, now: now)
    }
}
