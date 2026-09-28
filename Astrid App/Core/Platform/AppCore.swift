//  AppCore.swift
//  The app's one astrid-core session: the cache, the Outbox, sync and the live stream.
//
//  Everything the data layer does — reading tasks and lists, writing them, delivering the writes,
//  pulling what changed, listening to the live stream — happens in astrid-core, the shared Rust
//  core the Windows app runs on (docs/CORE_MIGRATION.md). This file starts it once, hands it the
//  Keychain, and passes on what it says moved to the services the views bind to.

import AstridCore
import Foundation

@MainActor
final class AppCore {
    static let shared = AppCore()

    /// The running core. Started on first use, so every service reaches the same one.
    let session: CoreSession

    private let relay = ChangeRelay()

    private init() {
        let testing = Self.isRunningUnitTests
        do {
            session = try CoreSession(
                // A unit-test run gets a throwaway cache and no background loops, so no test can
                // reach the network or someone's real data.
                cachePath: testing ? ":memory:" : Self.cacheURL.path,
                baseURL: Constants.API.baseURL,
                platform: Self.platform,
                credentials: CoreCredentials(),
                background: !testing)
        } catch {
            // The cache could not be opened — a corrupt file, a full disk. Starting over is better
            // than a data layer that is not there: the server has everything but unsent writes.
            AppLog.debug("❌ [AppCore] could not open the cache (\(error)); starting a fresh one")
            try? FileManager.default.removeItem(at: Self.cacheURL)
            session = try! CoreSession(
                cachePath: Self.cacheURL.path, baseURL: Constants.API.baseURL,
                platform: Self.platform, credentials: CoreCredentials(), background: !testing)
        }
        session.subscribe(relay)
        // The first launch after the move: carry Core Data's cache and the Swift Outbox's unsent
        // task and list writes over before anything reads the cache.
        if !testing {
            CoreUpgrade.runIfNeeded(session)
        }
    }

    /// Where the cache lives: Application Support, beside nothing else, so deleting the folder is a
    /// complete reset. Attachments the core downloads go in `attachments/` next to it.
    static var cacheURL: URL {
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

    /// Where a change goes: the services the views bind to, each reading back what it holds.
    fileprivate func route(_ change: CoreChange) {
        ListService.shared.coreDidChange(change)
        TaskService.shared.coreDidChange(change)
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
