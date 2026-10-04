//  AppCore.swift
//  The app's one astrid-core session: the cache, the Outbox, sync and the live stream.
//
//  Everything the data layer does — reading tasks and lists, writing them, delivering the writes,
//  pulling what changed, listening to the live stream — happens in astrid-core, the shared Rust
//  core the Windows app runs on (docs/CORE_MIGRATION.md). This file starts it once, hands it the
//  Keychain, and passes on what it says moved to the services the views bind to.

import AstridCore
import Combine
import Foundation

@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    /// The running core. Started on first use, so every service reaches the same one.
    let session: CoreSession

    private let relay = ChangeRelay()

    private init() {
        let testing = Self.isRunningUnitTests
        let cachePath = Self.cachePath(unitTesting: testing, uiTesting: UITestSession.isUITesting)
        do {
            session = try CoreSession(
                // A unit-test run gets a throwaway cache and no background loops, so no test can
                // reach the network or someone's real data. A UI-test run gets a scratch file.
                cachePath: cachePath,
                baseURL: Constants.API.baseURL,
                platform: Self.platform,
                credentials: CoreCredentials(),
                background: !testing)
        } catch {
            // The cache could not be opened — a corrupt file, a full disk. Starting over is better
            // than a data layer that is not there: the server has everything but unsent writes.
            AppLog.debug("❌ [AppCore] could not open the cache (\(error)); starting a fresh one")
            try? FileManager.default.removeItem(atPath: cachePath)
            session = try! CoreSession(
                cachePath: cachePath, baseURL: Constants.API.baseURL,
                platform: Self.platform, credentials: CoreCredentials(), background: !testing)
        }
        session.subscribe(relay)
        // The one answer to the network coming back: writes that waited for it go now, delivery
        // wakes, and the live stream starts over rather than waiting out a backoff chosen offline.
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable, object: nil, queue: .main
        ) { _ in
            _Concurrency.Task { @MainActor in AppCore.shared.networkRestored() }
        }
        // The first launch after the move: carry Core Data's cache and the Swift Outbox's unsent
        // task and list writes over before anything reads the cache.
        if Self.runsUpgrade(unitTesting: testing, uiTesting: UITestSession.isUITesting) {
            CoreUpgrade.runIfNeeded(session)
            GoogleLedgerUpgrade.start(session)
        }
    }

    /// Which cache a run opens (AITD-448).
    ///
    /// **A UI-test run never opens the user's.** UI tests share the shipping bundle id, so
    /// `cacheURL` is the user's own cache — journal included. Core Data and the Swift Outbox each
    /// gave a `-uiTesting` run a throwaway store; when the data layer moved here that isolation
    /// was left behind, and the offline Mac UI suite's list creates waited in the real journal
    /// until the user's signed-in app delivered them to the user's account. A scratch FILE rather
    /// than `:memory:`, because a UI-test run keeps the core's background loops running.
    nonisolated static func cachePath(unitTesting: Bool, uiTesting: Bool) -> String {
        if unitTesting { return ":memory:" }
        if uiTesting { return uiTestCacheURL.path }
        return cacheURL.path
    }

    /// The upgrade seeds from Core Data — a throwaway store under test — and then records that it
    /// is done in the REAL UserDefaults, which would mark the user's own upgrade finished.
    nonisolated static func runsUpgrade(unitTesting: Bool, uiTesting: Bool) -> Bool {
        !unitTesting && !uiTesting
    }

    /// One scratch cache per UI-test process, in the temp directory: every service reaches the
    /// same one, and nothing a run writes outlives it. Attachments land in `attachments/` beside it.
    nonisolated static let uiTestCacheURL: URL = {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AstridCore-uitest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("cache.sqlite")
    }()

    /// Where the cache lives: Application Support, beside nothing else, so deleting the folder is a
    /// complete reset. Attachments the core downloads go in `attachments/` next to it.
    nonisolated static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AstridCore", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("cache.sqlite")
    }

    static var platform: CorePlatform {
        #if os(macOS)
        return .mac
        #else
        return .ios
        #endif
    }

    nonisolated static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && !UITestSession.isUITesting
    }

    /// The services a change can concern.
    enum Audience: CaseIterable, Hashable {
        case lists, tasks, comments, chat, projects, members
    }

    /// Which services a change concerns (AITD-454).
    ///
    /// Every change used to go to all six, and a delivered task edit — announced as "something
    /// moved" — made every one of them re-read everything it held. Now a change goes only where it
    /// can matter. What the core cannot describe (`.unknown`, an undescribed delivery, an empty
    /// `.synced`) still reaches everyone, which is what every change did before.
    nonisolated static func audiences(for change: CoreChange) -> Set<Audience> {
        switch change {
        case .task, .needsSync:
            return [.tasks]
        case .list:
            return [.lists, .members]
        case .comments:
            return [.comments]
        case .chat:
            return [.chat]
        case .agentTyping:
            return [.comments, .chat]
        case .settings:
            return [.lists]
        case .synced(let taskIds, let listIds):
            if taskIds.isEmpty && listIds.isEmpty { return Set(Audience.allCases) }
            // The boards ride on every pass: their sync reports no ids.
            var audiences: Set<Audience> = [.projects]
            if !taskIds.isEmpty { audiences.insert(.tasks) }
            if !listIds.isEmpty { audiences.formUnion([.lists, .members]) }
            return audiences
        case .delivered(let delivery):
            if delivery.undescribed { return Set(Audience.allCases) }
            var audiences: Set<Audience> = []
            if !delivery.taskIds.isEmpty { audiences.insert(.tasks) }
            if !delivery.listIds.isEmpty { audiences.formUnion([.lists, .members, .projects]) }
            if !delivery.commentTaskIds.isEmpty { audiences.insert(.comments) }
            if !delivery.channelIds.isEmpty { audiences.insert(.chat) }
            return audiences
        case .unknown:
            return Set(Audience.allCases)
        case .remindersDue, .notifications, .stream:
            return []
        }
    }

    /// Where a change goes: the services it concerns, each reading back what it holds.
    fileprivate func route(_ change: CoreChange) {
        let audiences = Self.audiences(for: change)
        if audiences.contains(.lists) { ListService.shared.coreDidChange(change) }
        if audiences.contains(.tasks) { TaskService.shared.coreDidChange(change) }
        if audiences.contains(.comments) { CommentService.shared.coreDidChange(change) }
        if audiences.contains(.chat) { ChatService.shared.coreDidChange(change) }
        if audiences.contains(.projects) { ProjectService.shared.coreDidChange(change) }
        if audiences.contains(.members) { ListMemberService.shared.coreDidChange(change) }
        switch change {
        case .delivered(let delivery) where !delivery.undescribed:
            // The journal's counts came with the change: one answer for every badge, rather than
            // each service asking the core for the same numbers.
            let pending = delivery.pending + delivery.running
            TaskService.shared.showOutboxCounts(pending: pending, failed: delivery.failed)
            CommentService.shared.showOutboxCounts(pending: pending, failed: delivery.failed)
            ChatService.shared.showOutboxCounts(pending: pending, failed: delivery.failed)
            ListMemberService.shared.showOutboxCounts(pending: pending, failed: delivery.failed)
        case .settings:
            // Another device changed a setting, or the deployment its feature flags: the stream
            // says that something moved, not what.
            _Concurrency.Task {
                await UserSettingsService.shared.fetchSettings()
                await MyTasksPreferencesService.shared.fetchPreferences()
                await FeatureFlagService.shared.refreshIfStale(force: true)
            }
        case .needsSync:
            // An external provider reported changes (a GitHub webhook): wake the mirrors.
            NotificationCenter.default.post(name: .externalSyncRefresh, object: nil)
        case .stream(let live):
            isStreamLive = live
            if live {
                // What happened while the stream was down reached no one: one pass catches up.
                _Concurrency.Task { _ = try? await session.run(CoreCommand(kind: "sync")) }
            } else {
                // Nobody will say a reply finished while nothing is listening.
                ChatService.shared.typingAgent = [:]
                CommentService.shared.typingAgent = [:]
            }
        default:
            break
        }
    }

    /// Whether the core's live stream is connected — what a chat panel's fallback poll waits on.
    @Published private(set) var isStreamLive = false

    /// Send what is waiting in the core's journal now, rather than at its delivery loop's next turn.
    func drainJournal() async {
        _ = try? await session.run(CoreCommand(kind: "drain"))
    }

    private var networkObserver: NSObjectProtocol?

    /// The device is back online: send what waited for the network, and restart the stream.
    func networkRestored() {
        _Concurrency.Task { _ = try? await session.run(CoreCommand(kind: "networkRestored")) }
    }

    /// Drop the live stream and connect again now: the machine woke, the network came back, or
    /// somebody signed in. The core keeps it connected otherwise; there is nothing to start.
    func reconnectStream() {
        _Concurrency.Task { try? await session.run(CoreCommand(kind: "reconnectStream")) }
    }
}

/// Hears the core's changes on its threads and hands them to the main actor.
private final class ChangeRelay: CoreChangeListener, @unchecked Sendable {
    func onChange(changeJson: String) {
        let change = CoreChange(json: changeJson)
        _Concurrency.Task { @MainActor in AppCore.shared.route(change) }
    }
}

/// The core's credentials, kept where the app has always kept them.
///
/// The session cookie is the Keychain item `KeychainService` owns, so a person signed in before the
/// app spoke through the core stays signed in, and the Swift sign-in and session renewal (Sign in
/// with Apple, passkeys, `mobile-session`) keep writing the credential the core reads on every
/// request. Anything else the core stores goes in a Keychain item of its own.
final class CoreCredentials: CoreCredentialStore, @unchecked Sendable {
    private static let sessionCookieKey = "astrid.session-cookie"

    func get(key: String) -> String? {
        if key == Self.sessionCookieKey {
            return try? KeychainService.shared.getSessionCookie()
        }
        return try? KeychainService.shared.getValue(forKey: "core." + key)
    }

    func set(key: String, value: String) -> Bool {
        do {
            if key == Self.sessionCookieKey {
                try KeychainService.shared.saveSessionCookie(value)
            } else {
                try KeychainService.shared.setValue(value, forKey: "core." + key)
            }
            return true
        } catch {
            return false
        }
    }

    func delete(key: String) -> Bool {
        if key == Self.sessionCookieKey {
            try? KeychainService.shared.deleteSessionCookie()
        } else {
            try? KeychainService.shared.deleteValue(forKey: "core." + key)
        }
        // Deleting what is not there is still a delete.
        return true
    }
}

/// How the core's write journal is doing — the Settings screen's readout.
struct JournalStats: Decodable, Equatable {
    struct DeadLetter: Decodable, Hashable {
        let kind: String
        let error: String?
    }

    let pending: Int
    let running: Int
    let completed: Int
    let failed: Int
    /// The newest few refused writes and why.
    let deadLetters: [DeadLetter]

    /// No write refused. Pending and running are transient and fine.
    var isHealthy: Bool { failed == 0 }

    @MainActor
    static func load() async -> JournalStats? {
        try? await AppCore.shared.session.run(CoreCommand(kind: "outboxStats"), as: JournalStats.self)
    }

    /// Give every refused write another go.
    @MainActor
    static func retryDropped() async {
        _ = try? await AppCore.shared.session.run(CoreCommand(kind: "retryDeadLetters"))
    }
}
