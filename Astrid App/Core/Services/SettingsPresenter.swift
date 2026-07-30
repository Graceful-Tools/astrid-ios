import SwiftUI
import Combine

/**
 * SettingsPresenter
 *
 * Manages programmatic navigation to settings sub-pages.
 * Used for deep linking and internal navigation.
 */
@MainActor
class SettingsPresenter: ObservableObject {
    static let shared = SettingsPresenter()
    
    enum SettingsPage: String, Hashable, Identifiable {
        case account
        case profile
        case reminders
        case agents
        case apiAccess = "api-access"
        case chatgpt
        case contacts
        case appearance
        case debug
        case language
        case about
        
        var id: String { self.rawValue }
    }
    
    @Published var isSettingsPresented: Bool = false
    @Published var path = NavigationPath()
    
    private init() {}
    
    func navigateTo(page: SettingsPage) {
        self.isSettingsPresented = true
        self.path.append(page)
    }
    
    func openSettings() {
        self.isSettingsPresented = true
    }
    
    func dismiss() {
        self.isSettingsPresented = false
        self.path = NavigationPath()
    }
}

struct SettingsPresentationModifier: ViewModifier {
    @ObservedObject var presenter = SettingsPresenter.shared
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presenter.isSettingsPresented) {
                SettingsRootView()
            }
    }
}

struct SettingsRootView: View {
    @ObservedObject var presenter = SettingsPresenter.shared
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationStack(path: $presenter.path) {
            SettingsView()
                .navigationDestination(for: SettingsPresenter.SettingsPage.self) { page in
                    destinationView(for: page)
                }
        }
    }
    
    @ViewBuilder
    func destinationView(for page: SettingsPresenter.SettingsPage) -> some View {
        switch page {
        case .account, .profile:
            AccountSettingsView()
        case .reminders:
            ReminderSettingsView()
        case .agents, .chatgpt:
            AIAssistantSettingsView()
        case .apiAccess:
            AIAPIKeyManagerView()
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

extension View {
    func withSettingsPresentation() -> some View {
        self.modifier(SettingsPresentationModifier())
    }
}
