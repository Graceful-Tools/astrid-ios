//  EstimateCardModel.swift
//  What the estimate card draws, worked out from an estimate and the project's goals and guardrails
//  (ADEV-329; a port of web `lib/estimate-card.ts`, ADEV-280; spec astrid-web
//  `docs/specs/GOALS_GUARDRAILS_SIGNALS.md` → Surfaces). Shared by iOS and Mac, so both put the
//  reference line, the axis and the tiles where web does.
//
//  The numbers are the server's; this only places them: a range per goal and per guardrail with the
//  target or limit as a reference line, the impact / cost / opportunity tiles, the age and the
//  source. A section the estimator did not give is "not estimated" (nil), never zero.

import AstridCore
import Foundation

/// One range bar: a goal's or a guardrail's expected change, low to high.
struct EstimateRangeRow: Equatable, Identifiable {
    let id: String
    let statement: String
    let low: Double
    let high: Double
    /// The point estimate; nil on a rough estimate, which shows ranges only.
    let delta: Double?
    let unit: String?
    /// Where the target or limit sits on this row's axis (as a change from now), when it can be told.
    let reference: Double?
    /// Guardrails only; never on a rough estimate.
    let breachProbability: Double?
}

/// Reach × the first goal's range.
struct EstimateOpportunity: Equatable {
    let low: Double
    let high: Double
    let unit: String
    let period: String
}

struct EstimateCardModel {
    enum Age: Equatable {
        case now
        case minutes(Int)
        case hours(Int)
        case days(Int)
    }

    enum SourceKind: Equatable {
        case builtin
        case human
        case service(String)
    }

    let estimate: Estimate
    let goalRows: [EstimateRangeRow]
    let guardrailRows: [EstimateRangeRow]
    let age: Age?

    init(estimate: Estimate, goals: ProjectGoals?, now: Date) {
        self.estimate = estimate
        goalRows = Self.goalRows(estimate.goalImpacts, goals: goals, rough: estimate.rough)
        guardrailRows = Self.guardrailRows(estimate.guardrailImpacts, goals: goals, rough: estimate.rough)
        age = estimate.createdAt.flatMap { Self.age(createdAt: $0, now: now) }
    }

    // MARK: Tiles

    /// The first goal's range, or nil: not estimated.
    var impact: EstimateRangeRow? { goalRows.first }

    /// What the task costs, as a person reads money; nil when not estimated.
    var cost: String? { estimate.costMicrocents.map { Self.dollars(microcents: $0) } }

    var effortHours: Double? { estimate.effortHours }

    /// Reach × impact: needs both, otherwise not estimated.
    var opportunity: EstimateOpportunity? {
        guard let reach = estimate.reach, let primary = goalRows.first else { return nil }
        return EstimateOpportunity(low: primary.low * reach.count, high: primary.high * reach.count,
                                   unit: primary.unit ?? reach.unit, period: reach.period)
    }

    var source: SourceKind { Self.sourceKind(estimate.source ?? "") }

    // MARK: Rows

    /// One range per goal impact. The reference line is the change that would reach the target
    /// (`target − current`), and only exists when the goal's metric states both numbers.
    static func goalRows(_ impacts: [GoalImpact], goals: ProjectGoals?, rough: Bool) -> [EstimateRangeRow] {
        impacts.map { impact in
            let goal = goals?.goals.first { $0.id == impact.goalId }
            let metric = goal.flatMap { object($0.unmodeled["metric"]) }
            let target = metric.flatMap { number($0["target"]) }
            let current = metric.flatMap { number($0["current"]) }
            return EstimateRangeRow(
                id: impact.goalId,
                statement: goal?.statement ?? impact.goalId,
                low: impact.low ?? impact.delta,
                high: impact.high ?? impact.delta,
                delta: rough ? nil : impact.delta,
                unit: impact.unit,
                reference: target.flatMap { target in current.map { target - $0 } },
                breachProbability: nil)
        }
    }

    /// One range per guardrail impact. The reference line is the headroom to the threshold
    /// (`threshold − current`) when the guardrail's metric check has a reading to measure from.
    static func guardrailRows(_ impacts: [GuardrailImpact], goals: ProjectGoals?, rough: Bool) -> [EstimateRangeRow] {
        impacts.compactMap { impact in
            guard let low = impact.low ?? impact.delta, let high = impact.high ?? impact.delta else { return nil }
            let guardrail = goals?.guardrails.first { $0.id == impact.guardrailId }
            let check = guardrail.flatMap { object($0.unmodeled["check"]) }.flatMap { check -> [String: JSONValue]? in
                if case .string("metric")? = check["type"] { return check }
                return nil
            }
            let threshold = check.flatMap { number($0["threshold"]) }
            let current = check.flatMap { number($0["current"]) }
            return EstimateRangeRow(
                id: impact.guardrailId,
                statement: guardrail?.statement ?? impact.guardrailId,
                low: low,
                high: high,
                delta: rough ? nil : impact.delta,
                unit: check.flatMap { text($0["unit"]) },
                reference: threshold.flatMap { threshold in current.map { threshold - $0 } },
                breachProbability: rough ? nil : impact.breachProbability)
        }
    }

    // MARK: Axis

    /// The axis that holds every range, zero and every reference line, with a tenth of room either side.
    static func domain(_ rows: [EstimateRangeRow]) -> ClosedRange<Double> {
        var values = rows.flatMap { [$0.low, $0.high] + ($0.reference.map { [$0] } ?? []) }
        values.append(0)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let span = high - low
        let pad = span > 0 ? span * 0.1 : 1
        return (low - pad)...(high + pad)
    }

    /// Where a value sits along the axis, 0 to 1, clamped to it.
    static func fraction(_ value: Double, in domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0.5 }
        return min(1, max(0, (value - domain.lowerBound) / span))
    }

    // MARK: Words and numbers

    /// How long ago, at the one unit that reads naturally.
    static func age(createdAt: String, now: Date) -> Age? {
        guard let created = parseDate(createdAt) else { return nil }
        let minutes = Int(max(0, now.timeIntervalSince(created)) / 60)
        if minutes < 1 { return .now }
        if minutes < 60 { return .minutes(minutes) }
        let hours = minutes / 60
        if hours < 48 { return .hours(hours) }
        return .days(hours / 24)
    }

    static func sourceKind(_ source: String) -> SourceKind {
        switch source {
        case "builtin_llm": return .builtin
        case "human": return .human
        default: return .service(source.hasPrefix("service:") ? String(source.dropFirst("service:".count)) : source)
        }
    }

    /// Microcents in a dollar: a microcent is a millionth of a cent.
    private static let microcentsPerDollar = 100_000_000.0

    /// `$18`, `$2.5`, `$1.2k`: rounded the way a person reads money.
    static func dollars(microcents: Double) -> String {
        let dollars = microcents / microcentsPerDollar
        if dollars >= 1000 { return "$" + count(dollars) }
        if dollars >= 10 { return "$" + plain(dollars.rounded()) }
        return "$" + plain((dollars * 100).rounded() / 100)
    }

    /// `1.2k`, `41k`, `3.5M`: a count at a readable size.
    static func count(_ n: Double) -> String {
        let magnitude = abs(n)
        if magnitude >= 1e9 { return plain(fixed(n / 1e9)) + "B" }
        if magnitude >= 1e6 { return plain(fixed(n / 1e6)) + "M" }
        if magnitude >= 1e3 { return plain(fixed(n / 1e3)) + "k" }
        return plain(fixed(n))
    }

    /// `+1.2k`, `−300`: a signed count.
    static func signedCount(_ n: Double) -> String {
        n > 0 ? "+" + count(n) : count(n)
    }

    private static func fixed(_ n: Double) -> Double {
        abs(n) >= 100 ? n.rounded() : (n * 100).rounded() / 100
    }

    private static func plain(_ n: Double) -> String {
        n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        if case .object(let object)? = value { return object }
        return nil
    }

    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number)?: return number
        case .string(let text)?: return Double(text)
        default: return nil
        }
    }

    private static func text(_ value: JSONValue?) -> String? {
        if case .string(let text)? = value, !text.isEmpty { return text }
        return nil
    }
}

/// Whether task details offer the Estimate button, and its picker (web `EstimateControl`).
struct EstimateOffer: Equatable {
    let projectMode: Bool
    let projectId: String?
    let goals: ProjectGoals?
    let estimators: [EstimatorChoice]
    let isReadOnly: Bool

    /// Project Mode, a project, and goals or guardrails stated to estimate against.
    var hasSomethingToEstimate: Bool {
        projectMode && projectId != nil && !(goals?.isEmpty ?? true)
    }

    /// Asking writes a row, so a read-only task gets no button; nor does a deployment with no estimator.
    var showsButton: Bool { hasSomethingToEstimate && !estimators.isEmpty && !isReadOnly }

    /// One button; a picker only when there is more than one estimator to choose.
    var showsPicker: Bool { showsButton && estimators.count > 1 }

    /// An idea: an open card in a project's Inbox column, with no board status yet (web `board-card`).
    static func isIdea(_ task: Task) -> Bool {
        !task.completed && (task.statusRole ?? "").isEmpty
    }

    /// The project a task's estimate is read against: the first of its lists that is in one.
    static func projectId(for task: Task, lists: [TaskList]) -> String? {
        let membership = taskListMembershipIds(task)
        return lists.first { membership.contains($0.id) && $0.projectId != nil }?.projectId
    }
}
