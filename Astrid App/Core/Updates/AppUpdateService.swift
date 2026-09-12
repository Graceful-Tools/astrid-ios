import Foundation
import Combine

/// Knows whether a newer version of the app has shipped, and remembers being told to be quiet.
/// (AITD-383)
///
/// THROUGH THE SERVICE FACADE, never `AstridAPIClient` from a view (ASTRID.md rule 1) — the check
/// is kicked off from the UI, which is exactly the shape of call that rule exists to keep out of
/// views.
///
/// FAILURE IS SILENCE. `/api/v1/app-version` is served by astrid-web, which deploys by hand, so
/// for a while after this ships the endpoint simply will not be there. A 404, an offline device
/// and a malformed body all mean the same thing — we do not know — and none of them may produce a
/// banner, an alert or a retry storm. A version check that complains when it cannot check is
/// worse than no version check.
@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    /// The update to offer, or nil for "nothing to say". Views bind to this.
    @Published private(set) var availableUpdate: AvailableUpdate?

    struct AvailableUpdate: Equatable {
        let version: String
        let releaseNotes: String?
        let updateURL: URL
    }

    private let userDefaults: UserDefaults
    private let dismissedVersionKey = "appUpdateDismissedVersion"
    /// One check per launch is plenty: a release does not land while you are looking at the app,
    /// and polling would spend battery to tell you the same thing.
    private var hasCheckedThisLaunch = false

    /// How the latest version is fetched.
    ///
    /// Injected so the decision is testable without a network — and so the path this will actually
    /// be in for a while, the endpoint not existing, is testable at all. It still goes through
    /// `RemoteResourceService` by default, never the API client (ASTRID.md rule 1).
    private let fetch: (String) async throws -> AppVersionResponse

    init(userDefaults: UserDefaults = .standard,
         fetch: @escaping (String) async throws -> AppVersionResponse = { platform in
             try await RemoteResourceService.shared.getAppVersion(platform: platform)
         }) {
        self.userDefaults = userDefaults
        self.fetch = fetch
    }

    /// The version this instance compares against. Overridable so a test does not depend on the
    /// bundle's real marketing version, which changes with every release.
    var currentVersionOverride: String?

    /// This build's marketing version — the same string the Settings row shows.
    var currentVersion: String? {
        currentVersionOverride ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Which store to ask, and which store to send people to.
    private var platform: String {
        #if os(macOS)
        return "mac"
        #else
        return "ios"
        #endif
    }

    /// Ask the backend, and decide. Safe to call on every appearance; it only works once.
    func checkForUpdate() async {
        guard !hasCheckedThisLaunch else { return }
        // A modal card in the middle of a UI test run fails unrelated tests, the same reason the
        // review and notification prompts bow out.
        guard !UITestSession.suppressesInterruptingPrompts else { return }
        hasCheckedThisLaunch = true

        // EVERY failure is "unknown" — see the note above. There is deliberately no error path
        // that reaches the user.
        guard let response = try? await fetch(platform) else { return }

        guard AppVersionCheck.shouldPrompt(current: currentVersion,
                                           latest: response.latestVersion,
                                           dismissedVersion: userDefaults.string(forKey: dismissedVersionKey)),
              let latest = response.latestVersion,
              // No destination, no card. See `updateURL(from:)`.
              let destination = Self.updateURL(from: response.updateUrl) else { return }

        availableUpdate = AvailableUpdate(version: latest,
                                          releaseNotes: response.releaseNotes,
                                          updateURL: destination)
    }

    /// "Not now" — for this version only. Dismissing 1.9.2 must not swallow 1.9.3.
    func dismiss() {
        if let version = availableUpdate?.version {
            userDefaults.set(version, forKey: dismissedVersionKey)
        }
        availableUpdate = nil
    }

    /// Clear the card once the user has gone to the store, so it is not waiting when they return.
    func acknowledgeUpdateOpened() {
        dismiss()
    }

    /// Where the Update button goes — the server says, or there is no card.
    ///
    /// THE APP DOES NOT KNOW ITS OWN STORE URL. There is no App Store id anywhere in this
    /// repository: the review prompt uses `AppStore.requestReview`, which needs none. Hardcoding
    /// one here would mean inventing a number and shipping a link nobody checked, and a wrong
    /// store link is worse than no button — it sends people somewhere confidently.
    ///
    /// So the backend, which is already the source of truth for WHETHER there is an update
    /// (AITD-383), is also the source of truth for WHERE it is. An update we cannot send anyone
    /// to is not actionable, so it is not shown at all.
    ///
    /// Only real web and App Store schemes are accepted: this string arrives over the network and
    /// ends up in `openURL`, and "open whatever the server said" is not a thing to hand a client.
    static func updateURL(from serverValue: String?) -> URL? {
        guard let serverValue,
              let url = URL(string: serverValue),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "macappstore", "itms-apps"].contains(scheme) else { return nil }
        return url
    }
}
