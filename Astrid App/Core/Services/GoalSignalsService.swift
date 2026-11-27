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

    /// Tasks with an estimate request in flight, so the button reads "Estimating…" (ADEV-329).
    @Published private(set) var estimating: Set<String> = []
    /// This person asked for the `goal_signals` flag in this session.
    @Published private(set) var accessRequested = false

    /// Ask for an estimate: task id, estimator key, project id.
    typealias PostEstimate = @MainActor (String, String, String?) async throws -> EstimateRequestReply
    /// Ask for a gated feature by its key.
    typealias PostFeatureRequest = @MainActor (String) async throws -> Void

    private let readLinks: Read<TaskGoalLinks>
    private let readEstimate: Read<TaskEstimates>
    private let readExperiment: Read<TaskExperiments>
    private let postEstimate: PostEstimate
    private let postFeatureRequest: PostFeatureRequest
    private let experimentWrites: ExperimentWrites

    /// The feature flag behind every goal-signals route (web `GOAL_SIGNALS_FEATURE_KEY`).
    static let featureKey = "goal_signals"

    init(readLinks: Read<TaskGoalLinks>? = nil,
         readEstimate: Read<TaskEstimates>? = nil,
         readExperiment: Read<TaskExperiments>? = nil,
         postEstimate: PostEstimate? = nil,
         postFeatureRequest: PostFeatureRequest? = nil,
         experimentWrites: ExperimentWrites? = nil) {
        self.readLinks = readLinks ?? { try await Self.core.run(CoreCommand(kind: "getTaskGoalLinks", taskId: $0), as: TaskGoalLinks.self) }
        self.readEstimate = readEstimate ?? { try await Self.core.run(CoreCommand(kind: "getTaskEstimate", taskId: $0), as: TaskEstimates.self) }
        self.readExperiment = readExperiment ?? { try await Self.core.run(CoreCommand(kind: "getTaskExperiment", taskId: $0), as: TaskExperiments.self) }
        // The core has no write for estimates yet, so asking goes through the API client here,
        // and only here (ASTRID.md §0 rule 1). The answer is then read back through the core.
        self.postEstimate = postEstimate ?? {
            try await AstridAPIClient.shared.requestTaskEstimate(taskId: $0, estimator: $1, projectId: $2)
        }
        self.postFeatureRequest = postFeatureRequest ?? {
            try await AstridAPIClient.shared.requestFeatureAccess(featureKey: $0)
        }
        self.experimentWrites = experimentWrites ?? .api
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

    // MARK: - Asking for an estimate (ADEV-329)

    func isEstimating(taskId: String) -> Bool { estimating.contains(taskId) }

    /// Ask `estimator` for an estimate of the task against `projectId`'s goals. A person-only
    /// action: the server refuses an agent's. When it lands, the task's signals are read again,
    /// so the card shows the server's stored row, label and all.
    func requestEstimate(taskId: String, estimator: String, projectId: String?) async -> EstimateRequestOutcome {
        guard !estimating.contains(taskId) else { return .failed }
        estimating.insert(taskId)
        defer { estimating.remove(taskId) }
        do {
            let reply = try await postEstimate(taskId, estimator, projectId)
            if reply.pending == true { return .pending }
            await load(taskId: taskId)
            return .landed
        } catch {
            AppLog.debug("❌ [GoalSignals] estimate request failed: \((error as NSError).localizedDescription)")
            return Self.outcome(for: error)
        }
    }

    /// What a refusal means to the person: the flag not granted, no AI key for the built-in
    /// estimator, or anything else.
    nonisolated static func outcome(for error: Error) -> EstimateRequestOutcome {
        guard case AstridAPIError.httpError(_, let message) = error,
              let body = try? JSONDecoder().decode([String: JSONValue].self, from: Data(message.utf8)),
              case .string(let reason)? = body["reason"] else { return .failed }
        switch reason {
        case "not_granted": return .notGranted
        case "no_api_key": return .noKey
        default: return .failed
        }
    }

    /// Ask for the `goal_signals` flag (`POST /api/v1/feature-requests`). True when the server took it.
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            try await postFeatureRequest(Self.featureKey)
            accessRequested = true
            return true
        } catch {
            AppLog.debug("❌ [GoalSignals] access request failed: \((error as NSError).localizedDescription)")
            return false
        }
    }

    // MARK: - Experiments on a task (ADEV-330)

    /// Link an experiment or start a verification window, then read the task's experiments back.
    @discardableResult
    func linkExperiment(taskId: String, request: ExperimentLinkRequest, projectId: String?) async -> Bool {
        await write("link") { try await self.experimentWrites.link(taskId, request, projectId) } then: {
            await self.loadExperiment(taskId: taskId)
        }
    }

    @discardableResult
    func unlinkExperiment(taskId: String, experimentId: String) async -> Bool {
        await write("unlink") { try await self.experimentWrites.unlink(taskId, experimentId) } then: {
            await self.loadExperiment(taskId: taskId)
        }
    }

    /// Ask the services now; a task in the Pending results column may settle at once.
    @discardableResult
    func refreshExperiments(taskId: String) async -> Bool {
        await write("refresh") { try await self.experimentWrites.refresh(taskId) } then: {
            await self.loadExperiment(taskId: taskId)
        }
    }

    /// The project's experiment connectors. Only an owner or admin may read them; a refusal is
    /// an empty list, which leaves verification as the only choice.
    func experimentConnectors(projectId: String) async -> [ProjectConnector] {
        let all = (try? await experimentWrites.connectors(projectId)) ?? []
        return all.filter { $0.kind == "experiment" }
    }

    /// Add the Pending results preset column to a board (its owner only).
    @discardableResult
    func addResultsColumn(projectId: String) async -> Bool {
        await write("add results column") { try await self.experimentWrites.addResultsColumn(projectId) } then: {}
    }

    private func write(_ what: String, _ action: () async throws -> Void, then after: () async -> Void) async -> Bool {
        do {
            try await action()
        } catch {
            AppLog.debug("❌ [GoalSignals] \(what) failed: \((error as NSError).localizedDescription)")
            return false
        }
        await after()
        return true
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

/// What a task waits on, as the picker builds it (web `ExperimentLinkForm`).
enum ExperimentLinkRequest: Equatable, CustomStringConvertible {
    case experiment(connectorId: String, externalKey: String)
    case verification(days: Int)

    /// The longest verification window the server takes (web `VERIFICATION_MAX_DAYS`).
    static let maxVerificationDays = 90

    /// A whole number of days, 1 to 90, or nil.
    static func verificationDays(_ text: String) -> Int? {
        guard let days = Int(text.trimmingCharacters(in: .whitespaces)),
              (1...maxVerificationDays).contains(days) else { return nil }
        return days
    }

    struct Body: Encodable, Equatable {
        let kind: String
        var connectorId: String?
        var externalKey: String?
        var days: Int?
        var projectId: String?
    }

    /// `POST /api/v1/tasks/{id}/experiment`'s body.
    func body(projectId: String?) -> Body {
        switch self {
        case .experiment(let connectorId, let externalKey):
            return Body(kind: "experiment", connectorId: connectorId,
                        externalKey: externalKey.trimmingCharacters(in: .whitespacesAndNewlines), projectId: projectId)
        case .verification(let days):
            return Body(kind: "verification", days: days, projectId: projectId)
        }
    }

    var description: String {
        switch self {
        case .experiment(let connectorId, let key): return "experiment(\(connectorId), \(key))"
        case .verification(let days): return "verification(days: \(days))"
        }
    }
}

/// A project's connector to an outside service, without its credential.
nonisolated struct ProjectConnector: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    /// `metric`, `experiment` or `estimator`.
    var kind: String?
}

/// The experiment writes, as closures so tests can stand in for the server.
struct ExperimentWrites {
    var link: @MainActor (String, ExperimentLinkRequest, String?) async throws -> Void
    var unlink: @MainActor (String, String) async throws -> Void
    var refresh: @MainActor (String) async throws -> Void
    var connectors: @MainActor (String) async throws -> [ProjectConnector]
    var addResultsColumn: @MainActor (String) async throws -> Void

    /// The app's API client: the core has no experiment writes yet (ASTRID.md §0 rule 1 — only
    /// `GoalSignalsService` calls these).
    static var api: ExperimentWrites {
        ExperimentWrites(
            link: { try await AstridAPIClient.shared.linkTaskExperiment(taskId: $0, body: $1.body(projectId: $2)) },
            unlink: { try await AstridAPIClient.shared.unlinkTaskExperiment(taskId: $0, experimentId: $1) },
            refresh: { try await AstridAPIClient.shared.refreshTaskExperiments(taskId: $0) },
            connectors: { try await AstridAPIClient.shared.getProjectConnectors(projectId: $0) },
            addResultsColumn: { try await AstridAPIClient.shared.addProjectPresetColumn(projectId: $0, preset: GoalSignalsWording.resultsColumnRole) })
    }
}

/// The one-tap offer to add the Pending results column (web `ResultsColumnOffer`, ADEV-282).
enum ResultsColumnOffer {
    /// Once the task has a link, to the board's owner (the only person the statuses route lets add
    /// a column), on a board without the column, unless they said "Not now" for this board.
    static func shows(hasLinks: Bool, project: Project?, currentUserId: String?, dismissed: Bool) -> Bool {
        guard hasLinks, !dismissed, let project, let currentUserId, project.ownerId == currentUserId else { return false }
        return !(project.customStates ?? []).contains { $0.role == GoalSignalsWording.resultsColumnRole }
    }

    /// "Not now", remembered per board on this device.
    struct Dismissals {
        let defaults: UserDefaults
        private static let prefix = "resultsColumnOffer.dismissed."

        init(defaults: UserDefaults = .standard) { self.defaults = defaults }

        func isDismissed(projectId: String) -> Bool { defaults.bool(forKey: Self.prefix + projectId) }
        func dismiss(projectId: String) { defaults.set(true, forKey: Self.prefix + projectId) }
    }
}

/// What came of asking for an estimate.
enum EstimateRequestOutcome: Equatable {
    /// Stored; the signals were read again.
    case landed
    /// A service is still working; it appears when it is done.
    case pending
    /// The `goal_signals` flag is not granted: offer to request access.
    case notGranted
    /// The built-in estimator needs this person's AI key.
    case noKey
    case failed
}

/// The POST's answer, as far as the app needs it: 201 carries the estimate (read back through the
/// core instead), 202 says `pending`.
nonisolated struct EstimateRequestReply: Codable, Equatable, Sendable {
    var pending: Bool?
    var estimator: String?
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
    var unit: String?

    init(goalId: String, delta: Double, low: Double? = nil, high: Double? = nil, unit: String? = nil) {
        self.goalId = goalId
        self.delta = delta
        self.low = low
        self.high = high
        self.unit = unit
    }
}

/// An estimate's expected effect on one guardrail, and the chance it is breached (ADEV-329).
struct GuardrailImpact: Equatable {
    let guardrailId: String
    var delta: Double?
    var low: Double?
    var high: Double?
    var breachProbability: Double?
}

/// How many people a change reaches, per period (`{ count, unit, period }`).
struct EstimateReach: Equatable {
    let count: Double
    let unit: String
    let period: String
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
    var guardrailImpacts: [GuardrailImpact] = []
    var risk: SignalLevel?
    /// What the estimator says makes it risky, as it said it.
    var riskFactors: [String] = []
    var costMicrocents: Double?
    var effortHours: Double?
    var reach: EstimateReach?
    var confidence: SignalLevel?
    var rationale: String?
    /// The built-in estimator's answer: its ranges show under a "rough estimate" tag.
    var rough = false
    var createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, source, label, labelReasons, goalImpacts, guardrailImpacts, risk, costMicrocents, effortHours, reach
        case confidence, rationale, rough, createdAt
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
        if case .object(let risk)? = try? container.decodeIfPresent(JSONValue.self, forKey: .risk) {
            if case .string(let level)? = risk["level"] { self.risk = SignalLevel(rawValue: level) }
            if case .array(let factors)? = risk["factors"] {
                riskFactors = factors.compactMap { if case .string(let factor) = $0 { return factor } else { return nil } }
            }
        }
        if case .array(let impacts)? = try? container.decodeIfPresent(JSONValue.self, forKey: .goalImpacts) {
            goalImpacts = impacts.compactMap { item in
                guard case .object(let object) = item,
                      case .string(let goalId)? = object["goalId"],
                      let delta = Self.number(object["delta"]) else { return nil }
                return GoalImpact(goalId: goalId, delta: delta, low: Self.number(object["low"]),
                                  high: Self.number(object["high"]), unit: Self.text(object["unit"]))
            }
        }
        if case .array(let impacts)? = try? container.decodeIfPresent(JSONValue.self, forKey: .guardrailImpacts) {
            guardrailImpacts = impacts.compactMap { item in
                guard case .object(let object) = item, case .string(let id)? = object["guardrailId"] else { return nil }
                return GuardrailImpact(guardrailId: id, delta: Self.number(object["delta"]), low: Self.number(object["low"]),
                                       high: Self.number(object["high"]),
                                       breachProbability: Self.number(object["breachProbability"]))
            }
        }
        // Cost arrives as a number, or as a string where the server's BigInt would not fit one.
        switch try? container.decodeIfPresent(JSONValue.self, forKey: .costMicrocents) {
        case .number(let value)?: costMicrocents = value
        case .string(let value)?: costMicrocents = Double(value)
        default: break
        }
        effortHours = Self.number(try? container.decodeIfPresent(JSONValue.self, forKey: .effortHours))
        if case .object(let reach)? = try? container.decodeIfPresent(JSONValue.self, forKey: .reach),
           let count = Self.number(reach["count"]) {
            self.reach = EstimateReach(count: count, unit: Self.text(reach["unit"]) ?? "", period: Self.text(reach["period"]) ?? "")
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

extension Estimate {
    fileprivate static func number(_ value: JSONValue?) -> Double? {
        if case .number(let number)? = value { return number }
        return nil
    }

    fileprivate static func text(_ value: JSONValue?) -> String? {
        if case .string(let text)? = value, !text.isEmpty { return text }
        return nil
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

/// One metric an experiment service reports, as it reports it.
struct ExperimentMetric: Equatable {
    let metricKey: String
    let relDelta: Double
    var significant: Bool?
}

/// What the experiment service recommends: `start`, `continue`, `stop`, `ship` or `rollback`.
struct ExperimentRecommendation: Equatable {
    let action: String
    var reason: String?
}

/// An experiment link or a post-deploy verification window. The service's numbers are kept as
/// given: Astrid computes no statistics.
struct ExperimentLink: Decodable, Equatable, Identifiable {
    let id: String
    /// `experiment` or `verification`.
    var kind: String?
    /// The experiment's key in its service (ADEV-330), the row's title.
    var externalKey: String?
    var url: String?
    /// `pending`, `running`, `concluded`, `stopped` or `unknown`.
    var state: String
    /// `improving`, `flat`, `regressing` or `inconclusive`; `nil` until there is one.
    var verdict: String?
    var recommendation: ExperimentRecommendation?
    /// Only metrics with a relative delta: one without has nothing to say.
    var metrics: [ExperimentMetric] = []
    var decideBy: String?
    var fetchedAt: String?
    /// No data for 48 hours.
    var stale: Bool

    private enum CodingKeys: String, CodingKey {
        case id, kind, externalKey, url, state, verdict, recommendation, metrics, decideBy, fetchedAt, stale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        externalKey = try? container.decodeIfPresent(String.self, forKey: .externalKey)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? "unknown"
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        decideBy = try container.decodeIfPresent(String.self, forKey: .decideBy)
        fetchedAt = try? container.decodeIfPresent(String.self, forKey: .fetchedAt)
        stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        // The service's sections arrive as any JSON: read what is understood, never fail the link.
        if case .object(let object)? = try? container.decodeIfPresent(JSONValue.self, forKey: .recommendation),
           case .string(let action)? = object["action"] {
            var reason: String?
            if case .string(let text)? = object["reason"], !text.isEmpty { reason = text }
            recommendation = ExperimentRecommendation(action: action, reason: reason)
        }
        if case .array(let items)? = try? container.decodeIfPresent(JSONValue.self, forKey: .metrics) {
            metrics = items.compactMap { item in
                guard case .object(let object) = item,
                      case .string(let key)? = object["metricKey"],
                      case .number(let delta)? = object["relDelta"] else { return nil }
                var significant: Bool?
                if case .bool(let flag)? = object["significant"] { significant = flag }
                return ExperimentMetric(metricKey: key, relDelta: delta, significant: significant)
            }
        }
    }

    /// Still waiting on a result.
    var isOpen: Bool { state != "concluded" && state != "stopped" }

    /// `decideBy` as a date, for "Decide by …".
    var decideByDate: Date? {
        decideBy.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    var fetchedAtDate: Date? {
        guard let fetchedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: fetchedAt) { return date }
        return ISO8601DateFormatter().date(from: fetchedAt)
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

    // MARK: The experiment row (ADEV-330)

    /// The experiment's key, or "Experiment" / "Verification".
    static func experimentTitle(_ link: ExperimentLink) -> String {
        if link.kind == "verification" { return text("goalSignals.results.verification") }
        if let key = link.externalKey, !key.isEmpty { return key }
        return text("goalSignals.results.experiment")
    }

    /// `+4.2%` from 0.042, written as web writes it.
    static func relDelta(_ value: Double) -> String {
        let percent = value * 100
        let rounded = (percent * 10).rounded() / 10
        let body = String(format: "%.1f%%", rounded == 0 ? 0 : rounded)
        return rounded > 0 ? "+" + body : body
    }

    /// "conversion +4.2%", "aov −1.0% (not significant)".
    static func metricLine(_ metric: ExperimentMetric) -> String {
        let line = "\(metric.metricKey) \(relDelta(metric.relDelta))"
        guard metric.significant == false else { return line }
        return String(format: text("goalSignals.experiment.notSignificant"), line)
    }

    /// "Recommends ship: Conversion is up"; an action this build does not know is left unsaid.
    static func recommendation(_ value: ExperimentRecommendation) -> String? {
        let key: String
        switch value.action {
        case "start": key = "goalSignals.experiment.action.start"
        case "continue": key = "goalSignals.experiment.action.continue"
        case "stop": key = "goalSignals.experiment.action.stop"
        case "ship": key = "goalSignals.experiment.action.ship"
        case "rollback": key = "goalSignals.experiment.action.rollback"
        default: return nil
        }
        let line = String(format: text("goalSignals.experiment.recommends"), text(key))
        guard let reason = value.reason else { return line }
        return line + ": " + reason
    }

    /// "No data since 3 d ago", or "No data yet".
    static func noData(since date: Date?, now: Date = Date()) -> String {
        guard let date else { return text("goalSignals.experiment.noDataYet") }
        let age = EstimateCardModel.age(createdAt: ISO8601DateFormatter().string(from: date), now: now) ?? .now
        return String(format: text("goalSignals.experiment.noDataSince"), self.age(age))
    }

    // MARK: The estimate card (ADEV-329)

    /// "+1 % to +4 %": a row's range, each end with its unit.
    static func range(_ row: EstimateRangeRow) -> String {
        String(format: text("goalSignals.estimate.range"), withUnit(signed(row.low), row.unit), withUnit(signed(row.high), row.unit))
    }

    /// "(target change +3 %)", or nil without a reference.
    static func reference(_ row: EstimateRangeRow) -> String? {
        row.reference.map { String(format: text("goalSignals.estimate.reference"), withUnit(signed($0), row.unit)) }
    }

    /// "20% chance of breach".
    static func breach(_ probability: Double) -> String {
        String(format: text("goalSignals.estimate.breach"), percent(probability))
    }

    /// "High risk": the card's risk chip.
    static func riskChip(_ value: SignalLevel) -> String {
        String(format: text("goalSignals.estimate.riskChip"), level(value))
    }

    static func effort(_ hours: Double) -> String {
        String(format: text("goalSignals.estimate.effort"), hours.formatted(.number.precision(.fractionLength(0...1))))
    }

    /// "+2k to +8k users / month".
    static func opportunity(_ value: EstimateOpportunity) -> String {
        String(format: text("goalSignals.estimate.opportunityRange"),
               EstimateCardModel.signedCount(value.low), EstimateCardModel.signedCount(value.high), value.unit, value.period)
    }

    static func source(_ kind: EstimateCardModel.SourceKind) -> String {
        let name: String
        switch kind {
        case .builtin: name = text("goalSignals.estimate.sourceBuiltin")
        case .human: name = text("goalSignals.estimate.sourceHuman")
        case .service(let key): name = key
        }
        return String(format: text("goalSignals.estimate.source"), name)
    }

    static func age(_ age: EstimateCardModel.Age) -> String {
        switch age {
        case .now: return text("goalSignals.estimate.age.now")
        case .minutes(let n): return String(format: text("goalSignals.estimate.age.minutes"), n)
        case .hours(let n): return String(format: text("goalSignals.estimate.age.hours"), n)
        case .days(let n): return String(format: text("goalSignals.estimate.age.days"), n)
        }
    }

    /// What the person sees after asking, or nil when there is nothing to say (it landed).
    static func outcome(_ outcome: EstimateRequestOutcome) -> String? {
        switch outcome {
        case .landed: return nil
        case .pending: return text("goalSignals.estimate.pending")
        case .noKey: return text("goalSignals.estimate.noKey")
        case .notGranted: return text("goalSignals.estimate.notGranted")
        case .failed: return text("goalSignals.estimate.failed")
        }
    }

    private static func withUnit(_ value: String, _ unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return value }
        return unit == "%" ? value + unit : value + " " + unit
    }

    static func signed(_ value: Double) -> String {
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
