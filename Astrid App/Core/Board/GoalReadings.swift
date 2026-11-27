//  GoalReadings.swift
//  ADEV-321 (web ADEV-270/276, `lib/goals-guardrails.ts` goalProgress / goalFreshness /
//  goalSparkValues): what a goal's numbers say — progress toward the target, how fresh the reading
//  is, and the readings to draw as a sparkline. Display only; the server writes every number.

import AstridCore
import Foundation

/// A goal's measure as numbers, with an optional outside source (web `GoalMetric`, ADEV-270).
nonisolated struct GoalMetric: Decodable, Equatable, Sendable {
    enum Direction: String, Decodable, Sendable { case up, down }
    struct Source: Decodable, Equatable, Sendable {
        var connectorId: String
        var metricKey: String
    }

    var direction: Direction
    var unit: String?
    var target: Double?
    var baseline: Double?
    /// Server-written.
    var current: Double?
    /// ISO timestamp, server-written.
    var measuredAt: String?
    var source: Source?
    /// How old `current` may get before it reads as stale. Default 48.
    var staleAfterHours: Double?
}

/// One recorded change of a goal's `current` (web `GoalMeasurement`).
nonisolated struct GoalMeasurement: Decodable, Equatable, Sendable {
    var value: String
    var by: String
    var at: String
    var num: Double?
}

extension ProjectGoal {
    /// The typed metric, read from the pass-through keys. Read-only: the editor does not change
    /// it, and a save sends the stored block back exactly as it came (ADEV-319).
    var metric: GoalMetric? { unmodeled["metric"].flatMap { try? $0.decoded(as: GoalMetric.self) } }

    /// The recorded readings, oldest first. Empty when there are none or they do not read.
    var history: [GoalMeasurement] {
        unmodeled["history"].flatMap { try? $0.decoded(as: [GoalMeasurement].self) } ?? []
    }
}

private extension JSONValue {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}

nonisolated enum GoalReadings {
    struct Progress: Equatable {
        var met: Bool
        /// current/target, 0…100; nil when lower is better or the target is not positive.
        var percent: Int?
    }

    struct Freshness: Equatable {
        var measuredAt: Date
        /// Seconds since the reading.
        var age: TimeInterval
        var stale: Bool
    }

    static let defaultStaleAfterHours: Double = 48

    /// How far `current` is toward `target`. A metric with both numbers wins; otherwise the first
    /// number in each text, where a "≤"/"<"/"at most"/"max" target means lower is better. Nil
    /// when either side has no number, so a prose measure shows none.
    static func progress(_ goal: ProjectGoal) -> Progress? {
        let metric = goal.metric.flatMap { $0.target != nil && $0.current != nil ? $0 : nil }
        guard let target = metric?.target ?? firstNumber(goal.target),
              let current = metric?.current ?? firstNumber(goal.current) else { return nil }
        let lowerIsBetter = metric.map { $0.direction == .down } ?? targetReadsAsAtMost(goal.target)
        if lowerIsBetter { return Progress(met: current <= target, percent: nil) }
        if target <= 0 { return Progress(met: current >= target, percent: nil) }
        let percent = Int((current / target * 100).rounded())
        return Progress(met: current >= target, percent: max(0, min(100, percent)))
    }

    /// When the goal was last read and whether that is older than its `staleAfterHours`. The
    /// metric's reading time first, then the last history entry; nil without either.
    static func freshness(_ goal: ProjectGoal, now: Date = Date()) -> Freshness? {
        let metric = goal.metric
        guard let stamp = metric?.measuredAt ?? goal.history.last?.at, let at = parseDate(stamp) else { return nil }
        let age = max(0, now.timeIntervalSince(at))
        let hours = metric?.staleAfterHours.flatMap { $0 > 0 ? $0 : nil } ?? defaultStaleAfterHours
        return Freshness(measuredAt: at, age: age, stale: age > hours * 3600)
    }

    /// The numeric readings, oldest first.
    static func sparkValues(_ goal: ProjectGoal) -> [Double] {
        goal.history.compactMap(\.num).filter(\.isFinite)
    }

    private static func firstNumber(_ text: String?) -> Double? {
        guard let text, let range = text.range(of: #"-?\d+(?:[.,]\d+)?"#, options: .regularExpression) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    private static func targetReadsAsAtMost(_ target: String?) -> Bool {
        guard let target else { return false }
        return target.range(of: #"^\s*(≤|<=|<|at most|max)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
