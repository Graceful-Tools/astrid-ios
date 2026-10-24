//  MacWakeRecovery.swift
//  Astrid for Mac — bring live updates back after the Mac wakes (task de2764fb).
//
//  A desktop app sleeps constantly. While asleep the SSE stream dies, its bounded retries burn
//  against a network that is not there, and once exhausted NOTHING revived it: the app kept
//  running with no live updates until it was relaunched. Waking is the signal to start over.

#if os(macOS)
import AppKit
import Foundation

enum MacWakeRecovery {
    /// Only worth reconnecting when there is a real session to stream for — a signed-out or
    /// offline-only app has nothing to listen to. Pure, so the rule is tested.
    static func shouldReconnect(isAuthenticated: Bool, isOfflineOnly: Bool) -> Bool {
        isAuthenticated && !isOfflineOnly
    }

    nonisolated(unsafe) private static var observer: NSObjectProtocol?
    nonisolated(unsafe) private static var observedCenter: NotificationCenter?

    /// Watch for wake. Idempotent — a second call while watching adds no second observer, so one
    /// wake never reconnects twice. The center and the reconnect are injectable for tests
    /// (AITD-540); the app passes neither.
    @MainActor
    static func start(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
                      reconnect: @escaping @MainActor () -> Void = {
                          guard shouldReconnect(isAuthenticated: AuthManager.shared.isAuthenticated,
                                                isOfflineOnly: ConnectionModeManager.shared.isOfflineOnly) else { return }
                          AppLog.debug("☀️ [Wake] Reviving live updates after sleep")
                          AppCore.shared.networkRestored()
                      }) {
        guard observer == nil else { return }
        observedCenter = center
        observer = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            _Concurrency.Task { @MainActor in reconnect() }
        }
    }

    /// Stop watching — for tests, so each starts from nothing.
    @MainActor
    static func stop() {
        if let observer { observedCenter?.removeObserver(observer) }
        observer = nil
        observedCenter = nil
    }
}
#endif
