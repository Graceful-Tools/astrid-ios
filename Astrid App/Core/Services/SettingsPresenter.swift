import SwiftUI
import Combine

/**
 * SettingsPresenter
 *
 * Carries a request to show Settings — from a deep link — to the main panel, which owns where
 * Settings is drawn (AITD-458). The panel takes the request (`takeRequest()`), switches itself to
 * Settings, and the settings stack pushes `page`.
 *
 * It used to set a presented flag for a sheet modifier that nothing applied any more, so
 * every settings link — the web's Connections and Agent Hub links among them — opened nothing.
 */
@MainActor
final class SettingsPresenter: ObservableObject {
    static let shared = SettingsPresenter()

    /// The main panel's selection that shows Settings.
    static let panelId = "settings"

    struct Request: Equatable {
        /// The page to push on Settings, or nil for Settings itself.
        let page: SettingsPage?
    }

    /// A request not yet taken by the main panel. Held, not fired, so a link that arrives before
    /// the panel exists (a cold launch from an email) is still taken when it appears.
    @Published private(set) var request: Request?

    /// The page the settings stack shows on top of Settings; SettingsView binds to it.
    @Published var page: SettingsPage?

    private init() {}

    func navigateTo(page: SettingsPage) {
        request = Request(page: page)
    }

    func openSettings() {
        request = Request(page: nil)
    }

    /// Takes the pending request: sets the page to push and answers the panel to show, once.
    func takeRequest() -> String? {
        guard let request else { return nil }
        self.request = nil
        page = request.page
        return Self.panelId
    }

    func reset() {
        request = nil
        page = nil
    }
}

/// The screen for a settings page a link names.
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .account, .profile:
            AccountSettingsView()
        case .reminders:
            ReminderSettingsView()
        // The Agent Hub replaced AIAssistantSettingsView (AITD-297); the deep links kept pointing
        // at the old screen, and api-access at the provider-key manager, which is not what the
        // web page of that name ever was.
        case .agents, .chatgpt:
            AgentHubView()
        case .apiAccess, .connections:
            ConnectionsScreen()
        case .appearance:
            AppearanceSettingsView()
        case .language:
            LanguageSettingsView()
        case .contacts:
            Text(NSLocalizedString("debug.contacts_settings", comment: "Contacts Settings"))
                .navigationTitle(NSLocalizedString("contacts", comment: "Contacts"))
        case .debug:
            Text(NSLocalizedString("debug.debug_settings", comment: "Debug Settings"))
                .navigationTitle(NSLocalizedString("debug.settings", comment: "Debug"))
        case .about:
            Text(Brand.localized("debug.app_version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"))
                .navigationTitle(NSLocalizedString("about", comment: "About"))
        }
    }
}
