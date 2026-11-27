//  ProjectGoalMetric.swift
//  ADEV-331 (web ADEV-270/277, `lib/goals-guardrails.ts`): a goal's measured metric and an
//  enforced guardrail's metric check, editable. Both live in the keys the editor used to carry
//  untouched (`ProjectGoal.unmodeled["metric"]`, `ProjectGuardrail.unmodeled["check"]`, ADEV-319),
//  and they still carry what the server writes there (`current`, `measuredAt`) unchanged.
//
//  The server validates and normalises; this only edits the value. A cleared field is left out,
//  never sent as zero or "". Removing a metric sends an explicit `null`, because the server keeps
//  an omitted metric.

import AstridCore
import Foundation

/// Where a measured number comes from: a project connector and the metric's key in it.
nonisolated struct MetricSource: Equatable, Hashable, Sendable {
    var connectorId: String
    var metricKey: String

    init(connectorId: String, metricKey: String) {
        self.connectorId = connectorId
        self.metricKey = metricKey
    }

    init?(_ value: JSONValue?) {
        guard case .object(let object)? = value,
              case .string(let connectorId)? = object["connectorId"],
              case .string(let metricKey)? = object["metricKey"] else { return nil }
        self.init(connectorId: connectorId, metricKey: metricKey)
    }

    var isComplete: Bool {
        !connectorId.trimmingCharacters(in: .whitespaces).isEmpty && !metricKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var json: JSONValue {
        .object(["connectorId": .string(connectorId), "metricKey": .string(metricKey.trimmingCharacters(in: .whitespaces))])
    }
}

/// Which way is better for a goal's metric.
nonisolated enum MetricDirection: String, CaseIterable, Sendable {
    case up, down
}

extension ProjectGoal {
    private var metric: [String: JSONValue]? {
        if case .object(let object)? = unmodeled["metric"] { return object }
        return nil
    }

    /// The goal states a measured metric.
    var hasMetric: Bool { metric != nil }

    /// Start a metric, pointing up (web's default).
    mutating func addMetric() {
        unmodeled["metric"] = .object(["direction": .string(MetricDirection.up.rawValue)])
    }

    /// Clear it: an explicit null, which the server reads as "remove".
    mutating func removeMetric() {
        unmodeled["metric"] = .null
    }

    private mutating func setMetric(_ key: String, _ value: JSONValue?) {
        guard var object = metric else { return }
        object[key] = value
        unmodeled["metric"] = .object(object)
    }

    var metricDirection: MetricDirection {
        get {
            if case .string(let raw)? = metric?["direction"] { return MetricDirection(rawValue: raw) ?? .up }
            return .up
        }
        set { setMetric("direction", .string(newValue.rawValue)) }
    }

    var metricUnit: String? {
        get { if case .string(let unit)? = metric?["unit"] { return unit } else { return nil } }
        set { setMetric("unit", GoalMetricJSON.text(newValue)) }
    }

    var metricTarget: Double? {
        get { GoalMetricJSON.number(metric?["target"]) }
        set { setMetric("target", newValue.map(JSONValue.number)) }
    }

    var metricBaseline: Double? {
        get { GoalMetricJSON.number(metric?["baseline"]) }
        set { setMetric("baseline", newValue.map(JSONValue.number)) }
    }

    /// How old the reading may get before it counts as unknown (the server's default is 48).
    var metricStaleAfterHours: Double? {
        get { GoalMetricJSON.number(metric?["staleAfterHours"]) }
        set { setMetric("staleAfterHours", newValue.map(JSONValue.number)) }
    }

    var metricSource: MetricSource? {
        get { MetricSource(metric?["source"]) }
        set { setMetric("source", newValue.map(\.json)) }
    }
}

/// An enforced guardrail's metric check: pass while the reading is at most / at least the threshold.
nonisolated struct GuardrailMetricCheck: Equatable, Sendable {
    enum Op: String, CaseIterable, Sendable {
        case atMost = "<="
        case atLeast = ">="
    }

    var source: MetricSource
    var op: Op
    var threshold: Double?
    var unit: String?

    init(source: MetricSource, op: Op, threshold: Double?, unit: String? = nil) {
        self.source = source
        self.op = op
        self.threshold = threshold
        self.unit = unit
    }

    /// What the server accepts: a source and a threshold.
    var isComplete: Bool { source.isComplete && threshold != nil }
}

extension ProjectGuardrail {
    /// The metric check, or nil when there is none (or it is some other kind of check).
    var metricCheck: GuardrailMetricCheck? {
        get {
            guard case .object(let check)? = unmodeled["check"], case .string("metric")? = check["type"] else { return nil }
            let op = (check["op"].flatMap { if case .string(let raw) = $0 { return GuardrailMetricCheck.Op(rawValue: raw) } else { return nil } }) ?? .atMost
            var unit: String?
            if case .string(let text)? = check["unit"] { unit = text }
            return GuardrailMetricCheck(source: MetricSource(check["source"]) ?? MetricSource(connectorId: "", metricKey: ""),
                                        op: op, threshold: GoalMetricJSON.number(check["threshold"]), unit: unit)
        }
        set {
            guard let newValue else {
                unmodeled["check"] = nil
                return
            }
            // Keep what the server wrote there: the reading, when it was read, how old it may get.
            var check: [String: JSONValue] = [:]
            if case .object(let existing)? = unmodeled["check"] { check = existing }
            check["type"] = .string("metric")
            check["source"] = newValue.source.json
            check["op"] = .string(newValue.op.rawValue)
            check["threshold"] = newValue.threshold.map(JSONValue.number)
            check["unit"] = GoalMetricJSON.text(newValue.unit)
            unmodeled["check"] = .object(check)
        }
    }
}

extension ProjectGoalsUpdate {
    /// What may be sent: an unfinished metric check would be refused, so it is left out.
    var sanitized: ProjectGoalsUpdate {
        var copy = self
        copy.guardrails = guardrails.map { rail in
            var rail = rail
            if let check = rail.metricCheck, !check.isComplete { rail.metricCheck = nil }
            return rail
        }
        return copy
    }
}

private nonisolated enum GoalMetricJSON {
    static func number(_ value: JSONValue?) -> Double? {
        if case .number(let number)? = value { return number }
        return nil
    }

    /// A trimmed string, or nil (left out) when empty.
    static func text(_ value: String?) -> JSONValue? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return .string(value)
    }
}
