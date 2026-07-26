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

    /// Observe wake. Idempotent — installing twice would reconnect twice per wake.
    @MainActor
    static func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            _Concurrency.Task { @MainActor in
                guard shouldReconnect(isAuthenticated: AuthManager.shared.isAuthenticated,
                                      isOfflineOnly: ConnectionModeManager.shared.isOfflineOnly) else { return }
                print("☀️ [Wake] Reviving live updates after sleep")
                await SSEClient.shared.reconnectNow()
                try? await SyncManager.shared.performQuickSync()
            }
        }
    }
}
#endif
