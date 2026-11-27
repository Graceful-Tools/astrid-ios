import AstridCore
import Combine
import Foundation

/// What a task does for its project's goals: its goal links, its estimate and its experiment
/// results (ADEV-323; core ADEV-285, `services/goal_signals.rs`; spec astrid-core
/// `docs/GOAL_SIGNALS.md` §6).
///
/// The Canonical Control Point for these reads — views ask this, never an API client (ASTRID.md §0
/// rule 1). Everything goes through astrid-core, which caches each answer per task, so a board with
/// no network still draws what it last knew. **Nothing here computes**: the label, its reasons and
/// the verdict are the server's, kept as sent and only worded here (`GoalSignalsWording`).
///
/// A read the server refuses (the capability off, the flag not granted) throws in the core; here it
/// leaves that part `nil`, and a view draws no section for it, as the core asks.
@MainActor
final class GoalSignalsService: ObservableObject {
    static let shared = GoalSignalsService()

    typealias Read<T> = @MainActor (String) async throws -> T

    @Published private(set) var byTask: [String: GoalSignals] = [:]

    private let readLinks: Read<TaskGoalLinks>
    private let readEstimate: Read<TaskEstimates>
    private let readExperiment: Read<TaskExperiments>

    init(readLinks: Read<TaskGoalLinks>? = nil,
         readEstimate: Read<TaskEstimates>? = nil,
         readExperiment: Read<TaskExperiments>? = nil) {
        self.readLinks = readLinks ?? { try await Self.core.run(CoreCommand(kind: "getTaskGoalLinks", taskId: $0), as: TaskGoalLinks.self) }
        self.readEstimate = readEstimate ?? { try await Self.core.run(CoreCommand(kind: "getTaskEstimate", taskId: $0), as: TaskEstimates.self) }
        self.readExperiment = readExperiment ?? { try await Self.core.run(CoreCommand(kind: "getTaskExperiment", taskId: $0), as: TaskExperiments.self) }
    }

    private static var core: CoreSession { AppCore.shared.session }

    /// What is held for a task; `nil` until it has been read once.
    func signals(taskId: String) -> GoalSignals? { byTask[taskId] }

    /// Read all three for a task. Each part that fails is left out, never guessed.
    func load(taskId: String) async {
        let links = try? await readLinks(taskId)
        let estimates = try? await readEstimate(taskId)
        let experiments = try? await readExperiment(taskId)
        let signals = GoalSignals(links: links, estimates: estimates, experiments: experiments)
        if byTask[taskId] != signals { byTask[taskId] = signals }
    }

    /// Only the experiment results: what a card in the Pending results column needs.
    func loadExperiment(taskId: String) async {
        let experiments = try? await readExperiment(taskId)
        var signals = byTask[taskId] ?? GoalSignals()
        signals.experiments = experiments
        if byTask[taskId] != signals { byTask[taskId] = signals }
    }

    func coreDidChange(_ change: CoreChange) {
        _Concurrency.Task { await refresh(for: change) }
    }

    /// Read again what a change concerns: the announced task if it is held, or everything held
    /// when the core could not say what moved.
    func refresh(for change: CoreChange) async {
        switch change {
        case .taskGoalSignals(let taskId):
            guard byTask[taskId] != nil else { return }
            await load(taskId: taskId)
        case .unknown, .synced, .delivered:
            for taskId in Array(byTask.keys) { await load(taskId: taskId) }
        default:
            break
        }
    }
}

/// The three answers for one task. A `nil` part was refused, or has not been read.
struct GoalSignals: Equatable {
    var links: TaskGoalLinks?
    var estimates: TaskEstimates?
    var experiments: TaskExperiments?

    /// Whether task details have anything to draw: an estimate, or a goal the task serves.
    var hasDetail: Bool {
        estimates?.latest != nil || !(links?.links.isEmpty ?? true)
    }
}

// MARK: - Wire shapes (`astrid_core::services::goal_signals`)

struct GoalLink: Decodable, Equatable, Identifiable {
    let projectId: String
    var projectName: String?
    let goalId: String
    let statement: String
    /// `task` for the task's own link, `list` for one inherited from a list.
    var via: String?
    var listId: String?
    /// `person`, `agent` or `report`.
    var source: String?

    var id: String { "\(projectId):\(goalId)" }
}

struct TaskGoalLinks: Decodable, Equatable {
    var taskId: String = ""
    var links: [GoalLink] = []

    init(taskId: String, links: [GoalLink]) {
        self.taskId = taskId
        self.links = links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        links = try container.decodeIfPresent([GoalLink].self, forKey: .links) ?? []
    }

    private enum CodingKeys: String, CodingKey { case taskId, links }

    /// A goal's statement, to name a goal an estimate or a reason refers to by id.
    func statement(goalId: String) -> String? {
        links.first { $0.goalId == goalId }?.statement
    }
}

/// The trade-off label (`astrid_rules::tradeoff::Label`). A label this build does not know is no
/// label: the chip is not drawn.
enum TradeoffLabel: String, Equatable {
    case doNow = "do-now"
    case experimentFirst = "experiment-first"
    case needsReview = "needs-review"
    case dont
}

/// Risk and confidence's three steps (`astrid_rules::tradeoff::Level`).
enum SignalLevel: String, Equatable {
    case low, medium, high
}

/// An estimate's expected effect on one goal. `low` / `high` bound it when the estimator gave one.
struct GoalImpact: Equatable {
    let goalId: String
    let delta: Double
    var low: Double?
    var high: Double?
}

/// One reason for a label: its `code`, and the values that produced it, as sent.
struct EstimateReason: Equatable {
    let code: String
    let values: [String: JSONValue]

    func string(_ key: String) -> String? {
        if case .string(let value) = values[key] { return value }
        return nil
    }

    func number(_ key: String) -> Double? {
        if case .number(let value) = values[key] { return value }
        return nil
    }
}

struct Estimate: Decodable, Equatable {
    let id: String
    /// `builtin_llm`, `service:<key>` or `human`.
    var source: String?
    var label: TradeoffLabel?
    var reasons: [EstimateReason] = []
    var goalImpacts: [GoalImpact] = []
    var risk: SignalLevel?
    var confidence: SignalLevel?
    var rationale: String?
    /// The built-in estimator's answer: its ranges show under a "rough estimate" tag.
    var rough = false
    var createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, source, label, labelReasons, goalImpacts, risk, confidence, rationale, rough, createdAt
    }

    init(id: String, label: TradeoffLabel? = nil) {
        self.id = id
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        label = (try? container.decodeIfPresent(String.self, forKey: .label)).flatMap { $0.flatMap(TradeoffLabel.init(rawValue:)) }
        confidence = (try? container.decodeIfPresent(String.self, forKey: .confidence)).flatMap { $0.flatMap(SignalLevel.init(rawValue:)) }
        rationale = try? container.decodeIfPresent(String.self, forKey: .rationale)
        rough = (try? container.decodeIfPresent(Bool.self, forKey: .rough)) ?? false
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)

        // The sections whose shape the server owns arrive as any JSON: read what is understood,
        // skip what is not, never fail the whole estimate on one of them.
        if case .object(let risk)? = try? container.decodeIfPresent(JSONValue.self, forKey: .risk),
           case .string(let level)? = risk["level"] {
            self.risk = SignalLevel(rawValue: level)
        }
        if case .array(let impacts)? = try? container.decodeIfPresent(JSONValue.self, forKey: .goalImpacts) {
            goalImpacts = impacts.compactMap { item in
                guard case .object(let object) = item,
                      case .string(let goalId)? = object["goalId"],
                      case .number(let delta)? = object["delta"] else { return nil }
                func number(_ key: String) -> Double? {
                    if case .number(let value)? = object[key] { return value }
                    return nil
                }
                return GoalImpact(goalId: goalId, delta: delta, low: number("low"), high: number("high"))
            }
        }
        if case .array(let reasons)? = try? container.decodeIfPresent(JSONValue.self, forKey: .labelReasons) {
            self.reasons = reasons.compactMap { item in
                guard case .object(var object) = item, case .string(let code)? = object["code"] else { return nil }
                object.removeValue(forKey: "code")
                return EstimateReason(code: code, values: object)
            }
        }
    }
}

struct TaskEstimates: Decodable, Equatable {
    var taskId: String = ""
    var latest: Estimate?
    /// Newest first, at most 20.
    var history: [Estimate] = []

    init(taskId: String, latest: Estimate?, history: [Estimate]) {
        self.taskId = taskId
        self.latest = latest
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        latest = try container.decodeIfPresent(Estimate.self, forKey: .latest)
        history = try container.decodeIfPresent([Estimate].self, forKey: .history) ?? []
    }

    private enum CodingKeys: String, CodingKey { case taskId, latest, history }
}

/// An experiment link or a post-deploy verification window. The service's numbers are kept as
/// given: Astrid computes no statistics.
struct ExperimentLink: Decodable, Equatable, Identifiable {
    let id: String
    /// `experiment` or `verification`.
    var kind: String?
    var url: String?
    /// `pending`, `running`, `concluded`, `stopped` or `unknown`.
    var state: String
    /// `improving`, `flat`, `regressing` or `inconclusive`; `nil` until there is one.
    var verdict: String?
    var decideBy: String?
    /// No data for 48 hours.
    var stale: Bool

    private enum CodingKeys: String, CodingKey { case id, kind, url, state, verdict, decideBy, stale }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? "unknown"
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        decideBy = try container.decodeIfPresent(String.self, forKey: .decideBy)
        stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
    }

    /// `decideBy` as a date, for "Decide by …".
    var decideByDate: Date? {
        decideBy.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

struct TaskExperiments: Decodable, Equatable {
    var taskId: String = ""
    var experiments: [ExperimentLink] = []
    /// The task sits in the Pending results column.
    var inResultsColumn = false

    init(taskId: String, experiments: [ExperimentLink], inResultsColumn: Bool) {
        self.taskId = taskId
        self.experiments = experiments
        self.inResultsColumn = inResultsColumn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        experiments = try container.decodeIfPresent([ExperimentLink].self, forKey: .experiments) ?? []
        inResultsColumn = try container.decodeIfPresent(Bool.self, forKey: .inResultsColumn) ?? false
    }

    private enum CodingKeys: String, CodingKey { case taskId, experiments, inResultsColumn }
}

// MARK: - Wording

/// The words for what the server sent. Shared by iOS and Mac task details and the Pending results
/// card, so both platforms say the same thing.
enum GoalSignalsWording {
    /// The board column role whose cards draw the Pending results strip (core ADEV-274).
    static let resultsColumnRole = "results"

    private static func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    static func label(_ label: TradeoffLabel) -> String {
        switch label {
        case .doNow: return text("goalSignals.label.doNow")
        case .experimentFirst: return text("goalSignals.label.experimentFirst")
        case .needsReview: return text("goalSignals.label.needsReview")
        case .dont: return text("goalSignals.label.dont")
        }
    }

    static func level(_ level: SignalLevel) -> String {
        switch level {
        case .low: return text("goalSignals.level.low")
        case .medium: return text("goalSignals.level.medium")
        case .high: return text("goalSignals.level.high")
        }
    }

    private static func level(raw: String?) -> String? {
        raw.flatMap(SignalLevel.init(rawValue:)).map(level)
    }

    static func risk(_ value: SignalLevel) -> String {
        String(format: text("goalSignals.risk"), level(value))
    }

    static func confidence(_ value: SignalLevel) -> String {
        String(format: text("goalSignals.confidence"), level(value))
    }

    /// One reason in words; `nil` for a code this build does not know, which is left unsaid.
    static func reason(_ reason: EstimateReason, links: TaskGoalLinks?) -> String? {
        switch reason.code {
        case "noEstimate": return text("goalSignals.reason.noEstimate")
        case "stale": return text("goalSignals.reason.stale")
        case "guardrailAtRefuse", "guardrailAtReview":
            let id = reason.string("guardrailId") ?? ""
            let name = String(format: text("goalSignals.guardrailNamed"), id)
            let chance = reason.number("breachProbability").map(percent) ?? "?"
            let key = reason.code == "guardrailAtRefuse" ? "goalSignals.reason.guardrailAtRefuse" : "goalSignals.reason.guardrailAtReview"
            return String(format: text(key), name, chance)
        case "riskAtRefuse", "riskAtReview":
            guard let level = level(raw: reason.string("level")) else { return nil }
            return String(format: text("goalSignals.reason.risk"), level)
        case "riskUnknown": return text("goalSignals.reason.riskUnknown")
        case "guardrailsUnknown": return text("goalSignals.reason.guardrailsUnknown")
        case "confidenceLow": return text("goalSignals.reason.confidenceLow")
        case "experimentFirst": return text("goalSignals.reason.experimentFirst")
        case "builtinCapped": return text("goalSignals.reason.builtinCapped")
        case "goalImproves":
            let id = reason.string("goalId") ?? ""
            return String(format: text("goalSignals.reason.goalImproves"), links?.statement(goalId: id) ?? id)
        case "noGoalImproves": return text("goalSignals.reason.noGoalImproves")
        default: return nil
        }
    }

    /// The estimate in words, under its chip: reasons, each goal's change, then risk and confidence.
    static func summaryLines(_ estimate: Estimate, links: TaskGoalLinks?) -> [String] {
        var lines = estimate.reasons.compactMap { reason($0, links: links) }
        lines += estimate.goalImpacts.map { impact($0, statement: links?.statement(goalId: $0.goalId)) }
        if let value = estimate.risk { lines.append(risk(value)) }
        if let value = estimate.confidence { lines.append(confidence(value)) }
        return lines
    }

    /// "Grow signups: +2.5 (+1 to +4)": the expected change, and its range when there is one.
    static func impact(_ impact: GoalImpact, statement: String?) -> String {
        let name = statement ?? impact.goalId
        let delta = signed(impact.delta)
        if let low = impact.low, let high = impact.high {
            return String(format: text("goalSignals.impactRange"), name, delta, signed(low), signed(high))
        }
        return String(format: text("goalSignals.impact"), name, delta)
    }

    /// "Experiment · Running · Improving".
    static func resultLine(_ link: ExperimentLink) -> String {
        var parts: [String] = []
        parts.append(text(link.kind == "verification" ? "goalSignals.results.verification" : "goalSignals.results.experiment"))
        parts.append(state(link.state))
        if let verdict = link.verdict.flatMap(verdict) { parts.append(verdict) }
        return parts.joined(separator: " · ")
    }

    /// A Pending results card's line, iOS and Mac: "Experiment · Running · Improving · Decide by
    /// Dec 1", with the stale note after.
    static func cardLine(_ link: ExperimentLink) -> String {
        var parts = [resultLine(link)]
        if let date = link.decideByDate { parts.append(decideBy(date)) }
        if link.stale { parts.append(text("goalSignals.results.stale")) }
        return parts.joined(separator: " · ")
    }

    static func state(_ state: String) -> String {
        switch state {
        case "pending": return text("goalSignals.results.state.pending")
        case "running": return text("goalSignals.results.state.running")
        case "concluded": return text("goalSignals.results.state.concluded")
        case "stopped": return text("goalSignals.results.state.stopped")
        default: return text("goalSignals.results.state.unknown")
        }
    }

    static func verdict(_ verdict: String) -> String? {
        switch verdict {
        case "improving": return text("goalSignals.results.verdict.improving")
        case "flat": return text("goalSignals.results.verdict.flat")
        case "regressing": return text("goalSignals.results.verdict.regressing")
        case "inconclusive": return text("goalSignals.results.verdict.inconclusive")
        default: return nil
        }
    }

    static func decideBy(_ date: Date) -> String {
        String(format: text("goalSignals.results.decideBy"), date.formatted(date: .abbreviated, time: .omitted))
    }

    private static func signed(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "\u{2212}"
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)))
    }
}
