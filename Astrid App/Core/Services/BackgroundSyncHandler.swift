import BackgroundTasks
import Foundation
import os

private let logger = Logger(subsystem: Brand.logSubsystem, category: "BackgroundSync")

/// Handles background sync using BGTaskScheduler
/// Completes pending sync operations when the app goes to background
class BackgroundSyncHandler {
    static let shared = BackgroundSyncHandler()
    static let syncTaskIdentifier = "cc.astrid.app.sync"

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private init() {}

    /// Register background tasks with the system
    /// Must be called early in app lifecycle (before end of applicationDidFinishLaunching)
    func registerBackgroundTasks() {
        // Skip in test environment to prevent crashes
        guard !isRunningTests else {
            AppLog.debug("⚠️ [BackgroundSync] Skipping registration in test environment")
            return
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.syncTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                // The scheduler only hands back the type matching the request that
                // was submitted, so this cannot happen — but a force-cast here would
                // crash the app from a background launch, where nobody would see why.
                logger.error("Background task was not a BGProcessingTask; nothing to sync")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleSyncTask(processingTask)
        }
        AppLog.debug("✅ [BackgroundSync] Background task registered: \(Self.syncTaskIdentifier)")
    }

    /// Schedule a background sync task
    /// Called when the app goes to background to sync pending changes
    func scheduleBackgroundSync() {
        guard !isRunningTests else { return }

        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            AppLog.debug("✅ [BackgroundSync] Scheduled background sync")
        } catch {
            // Logged at Release level on purpose. This throw is how the app spent its
            // whole life never syncing in the background: UIBackgroundModes was missing,
            // BGTaskScheduler answered .unavailable every time, and a debug-only log
            // meant no shipping build ever said so.
            logger.error(
                "Failed to schedule background sync: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Handle the background sync task when it runs
    private func handleSyncTask(_ task: BGProcessingTask) {
        AppLog.debug("🔄 [BackgroundSync] Starting background sync task...")

        task.expirationHandler = {
            AppLog.debug("⚠️ [BackgroundSync] Task expired before completion")
            task.setTaskCompleted(success: false)
        }

        _Concurrency.Task { @MainActor in
            do {
                try await SyncManager.shared.performQuickSync()
                AppLog.debug("✅ [BackgroundSync] Background sync completed successfully")
                task.setTaskCompleted(success: true)
            } catch {
                AppLog.debug("❌ [BackgroundSync] Background sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}
