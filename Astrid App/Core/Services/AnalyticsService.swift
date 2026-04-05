import Foundation
import UIKit
import PostHog

/// Analytics service using PostHog for event tracking
/// Tracks user actions, task events, and engagement metrics
@MainActor
class AnalyticsService {
    static let shared = AnalyticsService()

    private var isConfigured = false

    private init() {
        configure()
    }

    // MARK: - Configuration

    private func configure() {
        // PostHog configuration
        // API key should match NEXT_PUBLIC_POSTHOG_KEY from web
        let posthogKey = Constants.Analytics.posthogKey

        guard !posthogKey.isEmpty, posthogKey != "your_posthog_project_api_key" else {
            print("⚠️ [Analytics] PostHog key not configured - analytics disabled")
            return
        }

        let config = PostHogConfig(apiKey: posthogKey, host: Constants.Analytics.posthogHost)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false // We'll track manually for more control
        config.sessionReplay = false // Disable session replay — causes SwiftUI view hierarchy warnings

        PostHogSDK.shared.setup(config)
        isConfigured = true
        print("✅ [Analytics] PostHog configured successfully")
    }

    // MARK: - User Identification

    /// Identify the user after successful authentication
    func identify(userId: String, email: String?, name: String?) {
        guard isConfigured else { return }

        var properties: [String: Any] = [
            "platform": "ios"
        ]

        if let email = email {
            properties["email"] = email
        }
        if let name = name {
            properties["name"] = name
        }

        PostHogSDK.shared.identify(userId, userProperties: properties)

        // Set signup date only once (for cohort analysis)
        PostHogSDK.shared.capture("$set_once", properties: [
            "$set_once": [
                "signup_date": ISO8601DateFormatter().string(from: Date()),
                "initial_platform": "ios"
            ]
        ])

        print("📊 [Analytics] User identified: \(userId)")
    }

    /// Reset user identity on logout
    func reset() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
        print("📊 [Analytics] User reset")
    }

    // MARK: - Auth Events

    func trackSignUp(method: String) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("user_signed_up", properties: [
            "method": method,
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked sign up via \(method)")
    }

    func trackLogin(method: String) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("user_logged_in", properties: [
            "method": method,
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked login via \(method)")
    }

    func trackLogout() {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("user_logged_out", properties: [
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked logout")
    }

    // MARK: - Task Events

    struct TaskEventProps {
        let taskId: String
        let listId: String?
        let hasDescription: Bool
        let hasDueDate: Bool
        let hasReminder: Bool
        let priority: Int
        let isRepeating: Bool

        init(taskId: String, listId: String? = nil, hasDescription: Bool = false,
             hasDueDate: Bool = false, hasReminder: Bool = false,
             priority: Int = 0, isRepeating: Bool = false) {
            self.taskId = taskId
            self.listId = listId
            self.hasDescription = hasDescription
            self.hasDueDate = hasDueDate
            self.hasReminder = hasReminder
            self.priority = priority
            self.isRepeating = isRepeating
        }

        var dictionary: [String: Any] {
            var dict: [String: Any] = [
                "taskId": taskId,
                "hasDescription": hasDescription,
                "hasDueDate": hasDueDate,
                "hasReminder": hasReminder,
                "priority": priority,
                "isRepeating": isRepeating,
                "platform": "ios"
            ]
            if let listId = listId {
                dict["listId"] = listId
            }
            return dict
        }
    }

    func trackTaskCreated(_ props: TaskEventProps) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("task_created", properties: props.dictionary)
        print("📊 [Analytics] Tracked task created: \(props.taskId)")
    }

    func trackTaskCompleted(_ props: TaskEventProps, source: String = "checkbox") {
        guard isConfigured else { return }
        var properties = props.dictionary
        properties["completionSource"] = source
        PostHogSDK.shared.capture("task_completed", properties: properties)
        print("📊 [Analytics] Tracked task completed: \(props.taskId)")
    }

    func trackTaskUncompleted(_ props: TaskEventProps) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("task_uncompleted", properties: props.dictionary)
        print("📊 [Analytics] Tracked task uncompleted: \(props.taskId)")
    }

    func trackTaskDeleted(_ props: TaskEventProps) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("task_deleted", properties: props.dictionary)
        print("📊 [Analytics] Tracked task deleted: \(props.taskId)")
    }

    func trackTaskEdited(_ props: TaskEventProps, fieldsChanged: [String]) {
        guard isConfigured else { return }
        var properties = props.dictionary
        properties["fieldsChanged"] = fieldsChanged
        PostHogSDK.shared.capture("task_edited", properties: properties)
        print("📊 [Analytics] Tracked task edited: \(props.taskId)")
    }

    func trackTaskViewed(taskId: String, listId: String?) {
        guard isConfigured else { return }
        var properties: [String: Any] = [
            "taskId": taskId,
            "platform": "ios"
        ]
        if let listId = listId {
            properties["listId"] = listId
        }
        PostHogSDK.shared.capture("task_viewed", properties: properties)
    }

    // MARK: - List Events

    func trackListCreated(
        listId: String,
        isVirtual: Bool = false,
        hasImage: Bool = false,
        isShared: Bool = false,
        hasGitIntegration: Bool = false,
        isPublic: Bool = false
    ) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("list_created", properties: [
            "listId": listId,
            "isVirtual": isVirtual,
            "hasImage": hasImage,
            "isShared": isShared,
            "hasGitIntegration": hasGitIntegration,
            "isPublic": isPublic,
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked list created: \(listId)")
    }

    func trackListEdited(listId: String, fieldsChanged: [String]) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("list_edited", properties: [
            "listId": listId,
            "fieldsChanged": fieldsChanged,
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked list edited: \(listId)")
    }

    func trackListDeleted(listId: String, taskCount: Int = 0) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("list_deleted", properties: [
            "listId": listId,
            "taskCount": taskCount,
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked list deleted: \(listId)")
    }

    func trackListShared(listId: String, memberCount: Int) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("list_shared", properties: [
            "listId": listId,
            "memberCount": memberCount,
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked list shared: \(listId)")
    }

    // MARK: - Comment Events

    func trackCommentAdded(taskId: String, listId: String?, hasAttachment: Bool = false) {
        guard isConfigured else { return }
        var properties: [String: Any] = [
            "taskId": taskId,
            "hasAttachment": hasAttachment,
            "platform": "ios"
        ]
        if let listId = listId {
            properties["listId"] = listId
        }
        PostHogSDK.shared.capture("comment_added", properties: properties)
        print("📊 [Analytics] Tracked comment added to: \(taskId)")
    }

    // MARK: - Reminder Events

    func trackReminderSet(taskId: String, reminderType: String) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("reminder_set", properties: [
            "taskId": taskId,
            "reminderType": reminderType,
            "platform": "ios"
        ])
        print("📊 [Analytics] Tracked reminder set: \(taskId)")
    }

    // MARK: - Screen Events

    func trackScreenView(_ screenName: String, properties: [String: Any]? = nil) {
        guard isConfigured else { return }
        var props: [String: Any] = [
            "screen_name": screenName,
            "platform": "ios"
        ]
        if let additional = properties {
            props.merge(additional) { _, new in new }
        }
        PostHogSDK.shared.capture("$screen", properties: props)
    }

    // MARK: - Session Events

    func trackSessionStart() {
        guard isConfigured else { return }
        PostHogSDK.shared.capture("session_started", properties: [
            "platform": "ios",
            "device_model": UIDevice.current.model,
            "system_version": UIDevice.current.systemVersion,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier
        ])
        print("📊 [Analytics] Tracked session start")
    }
}
