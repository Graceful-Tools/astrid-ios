import Foundation
import StoreKit
import UIKit
import Combine

/// Manages prompting users to review the app
/// First asks if they love using Astrid, then directs to appropriate action
@MainActor
class ReviewPromptManager: ObservableObject {
    static let shared = ReviewPromptManager()

    private let userDefaults = UserDefaults.standard

    // UserDefaults keys
    private let promptCountKey = "reviewPromptCount"
    private let lastPromptDateKey = "lastReviewPromptDate"
    private let hasReviewedKey = "hasReviewedApp"

    // Configuration
    private let minDaysBetweenPrompts = 30
    private let minTasksBeforePrompt = 5

    /// Published state for UI binding - shows initial "love Astrid?" prompt
    @Published var showLovePrompt = false

    /// Published state for showing the feedback/issue prompt
    @Published var showFeedbackPrompt = false

    private init() {}

    // MARK: - Public API

    /// Check if we should prompt the user for a review
    /// Should be called after user completes significant actions (task creation, completion, etc.)
    func checkAndPromptForReview() async {
        guard await shouldPromptForReview(isUITesting: UITestSession.suppressesInterruptingPrompts) else {
            return
        }

        // Show the prompt
        await MainActor.run {
            showLovePrompt = true
        }

        // Record this prompt attempt
        recordPromptAttempt()
    }

    /// Whether the review ask is due — with the run's nature passed in, so a test can ask
    /// without relaunching the process under a flag.
    ///
    /// A UI-test run never prompts (task b86c97c5). It is armed five seconds after sign-in,
    /// which lands squarely inside a suite that signs in on purpose, and a modal alert makes
    /// every element beneath it unhittable.
    func shouldPromptForReview(isUITesting: Bool) async -> Bool {
        if isUITesting { return false }

        // Don't prompt if user has already reviewed
        if userDefaults.bool(forKey: hasReviewedKey) {
            return false
        }

        // Check time since last prompt
        if let lastPromptDate = userDefaults.object(forKey: lastPromptDateKey) as? Date {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPromptDate, to: Date()).day ?? 0
            if daysSinceLastPrompt < minDaysBetweenPrompts {
                return false
            }
        }

        // Check if user has used the app enough
        let taskCount = await getCompletedTaskCount()
        if taskCount < minTasksBeforePrompt {
            return false
        }

        return true
    }

    /// Called when user taps "Yes, I love it!" - shows the native App Store review prompt
    func handleLoveResponse() async {
        // Mark that user has reviewed (or at least been prompted for review)
        userDefaults.set(true, forKey: hasReviewedKey)

        // Request App Store review
        // This respects Apple's limits (3 times per 365 days)
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            if #available(iOS 18.0, *) {
                // Use modern StoreKit API for iOS 18+
                AppStore.requestReview(in: scene)
            } else {
                // Fall back to older API for iOS 17 and below
                SKStoreReviewController.requestReview(in: scene)
            }
        }
    }

    /// Called when user taps "Not really" - shows feedback/issue prompt
    func handleNoLoveResponse() {
        showFeedbackPrompt = true
    }

    /// Opens the Bugs and Feedback list so user can report an issue
    func openFeedbackForm() {
        print("🎯 [ReviewPrompt] Opening Bugs and Feedback list")
        ListPresenter.shared.showPublicList(
            listId: Constants.Lists.bugsAndRequestsListId,
            name: "Bugs & Feedback"
        )
    }

    /// Opens the app's support/contact page via email
    func openSupportEmail() {
        let email = Brand.supportEmail
        let subject = "\(Brand.appName) App Feedback"
        let urlString = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject)"

        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Private Helpers

    private func recordPromptAttempt() {
        let currentCount = userDefaults.integer(forKey: promptCountKey)
        userDefaults.set(currentCount + 1, forKey: promptCountKey)
        userDefaults.set(Date(), forKey: lastPromptDateKey)
    }

    /// Get the number of completed tasks (used to determine if user is engaged enough)
    private func getCompletedTaskCount() async -> Int {
        // Get completed tasks from TaskService
        let taskService = TaskService.shared
        let completedTasks = taskService.tasks.filter { $0.completed }
        return completedTasks.count
    }

    /// Reset prompt tracking (useful for testing)
    func resetPromptTracking() {
        userDefaults.removeObject(forKey: promptCountKey)
        userDefaults.removeObject(forKey: lastPromptDateKey)
        userDefaults.removeObject(forKey: hasReviewedKey)
    }
}
