import SwiftUI
import Contacts

struct SettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var showingSignOutAlert = false
    @State private var isReady = false

    // Debug mode toggles (stored in UserDefaults like web app)
    @AppStorage("toast-debug-mode") private var toastDebugMode = false
    @AppStorage("reminder-debug-mode") private var reminderDebugMode = false


    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header
                FloatingTextHeader(NSLocalizedString("settings", comment: ""), icon: "gearshape", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                // Content — defer heavy sections until after navigation animation
                List {
                if !isReady {
                    // Lightweight placeholder so the view pushes instantly
                    Section {
                        Color.clear.frame(height: 0)
                    }
                } else {
                    // Sync section
                    SettingsSyncSection()

                // Features section
                Section(NSLocalizedString("features", comment: "")) {
                    NavigationLink(destination: LazyView { ReminderSettingsView() }) {
                        Label(NSLocalizedString("reminders", comment: ""), systemImage: "bell")
                    }
                }

                // Exploratory Features section
                Section(NSLocalizedString("exploratory_features", comment: "")) {
                    NavigationLink(destination: LazyView { DefaultAgentPickerView() }) {
                        HStack {
                            Image("AstridCharacter")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                            Text("Astrid's AI")
                        }
                    }

                    NavigationLink(destination: LazyView { AIAssistantSettingsView() }) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("ai_assistant", comment: ""))
                        }
                    }

                    NavigationLink(destination: LazyView { OpenClawSettingsView() }) {
                        HStack {
                            Image("ai-openclaw")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                            Text(NSLocalizedString("settings.openclaw.title", comment: ""))
                        }
                    }

                    NavigationLink(destination: LazyView { AppleRemindersSettingsView() }) {
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundColor(.blue)
                            Text(NSLocalizedString("apple_reminders", comment: ""))
                        }
                    }
                }

                // Preferences section
                    SettingsPreferencesSection()

                // Contacts section
                    SettingsContactsSection()

                // Debug settings (matching web app)
                #if DEBUG
                Section(NSLocalizedString("debug.settings", comment: "")) {
                    NavigationLink(destination: ServerSettingsView()) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("debug.server_config", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(String(format: NSLocalizedString("debug.current_server", comment: ""), Constants.API.baseURL))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                    }

                    Toggle(isOn: $toastDebugMode) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("debug.toast_debug_mode", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("debug.toast_debug_desc", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $reminderDebugMode) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("debug.reminder_debug_mode", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("debug.reminder_debug_desc", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)
                }

                Section(NSLocalizedString("debug.test_prompts", comment: "")) {
                    Button {
                        triggerLovePrompt()
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.pink)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("debug.test_love_prompt", comment: ""))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text(NSLocalizedString("debug.test_love_prompt_desc", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        resetPromptTracking()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("debug.reset_prompt_tracking", comment: ""))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text(NSLocalizedString("debug.reset_prompt_tracking_desc", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                #endif

                // Account section
                Section(NSLocalizedString("account", comment: "")) {
                    NavigationLink(destination: LazyView { AccountSettingsView() }) {
                        HStack {
                            Image(systemName: "person.circle")
                                .foregroundColor(Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("account_access", comment: ""))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text(NSLocalizedString("profile.account_access_full_desc", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                    }
                }

                // App info
                Section(NSLocalizedString("about", comment: "")) {
                    HStack {
                        Text(NSLocalizedString("version", comment: ""))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }

                    HStack {
                        Text(NSLocalizedString("build", comment: ""))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                }

                // Sign out (for signed-in users) or Create Account (for local users)
                if authManager.isLocalOnlyMode {
                    Section {
                        NavigationLink(destination: SignInPromptView().environmentObject(authManager)) {
                            HStack {
                                Spacer()
                                Label(NSLocalizedString("auth.create_account", comment: ""), systemImage: "person.crop.circle.badge.plus")
                                    .foregroundColor(Theme.accent)
                                Spacer()
                            }
                        }
                    } footer: {
                        Text(NSLocalizedString("auth.create_account_footer", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                } else {
                    Section {
                        Button(role: .destructive) {
                            showingSignOutAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Label(NSLocalizedString("sign_out", comment: ""), systemImage: "rectangle.portrait.and.arrow.right")
                                Spacer()
                            }
                        }
                    }
                }
                } // end isReady else
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .onAppear {
                    if !isReady {
                        // Defer content load until after push animation completes
                        DispatchQueue.main.async { isReady = true }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
        .alert(NSLocalizedString("sign_out", comment: ""), isPresented: $showingSignOutAlert) {
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("sign_out", comment: ""), role: .destructive) {
                _Concurrency.Task {
                    try? await authManager.signOut()
                }
            }
        } message: {
            Text(NSLocalizedString("are_you_sure_sign_out", comment: ""))
        }
    }

    #if DEBUG
    private func openTestFlightFeedback() {
        // Open TestFlight app to send feedback
        // itms-beta:// opens TestFlight directly
        if let url = URL(string: "itms-beta://") {
            UIApplication.shared.open(url)
        }
    }

    private func triggerLovePrompt() {
        ReviewPromptManager.shared.showLovePrompt = true
    }

    private func resetPromptTracking() {
        ReviewPromptManager.shared.resetPromptTracking()
    }
    #endif
}

// MARK: - Extracted Sections (isolate @ObservedObject re-renders)

/// Sync section — only re-renders when SyncManager publishes
private struct SettingsSyncSection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var syncManager = SyncManager.shared

    var body: some View {
        Section(NSLocalizedString("sync", comment: "")) {
            HStack {
                Label(NSLocalizedString("last_sync", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                if let lastSync = syncManager.lastSyncDate {
                    Text(lastSync, style: .relative)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                } else {
                    Text(NSLocalizedString("never", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }

            Button {
                _Concurrency.Task {
                    try? await syncManager.performFullSync()
                }
            } label: {
                HStack {
                    Label(NSLocalizedString("sync_now", comment: ""), systemImage: "arrow.clockwise")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Spacer()
                    if syncManager.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(syncManager.isSyncing)
        }
    }
}

/// Preferences section — only re-renders when UserSettingsService publishes
private struct SettingsPreferencesSection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var userSettings = UserSettingsService.shared

    var body: some View {
        Section(NSLocalizedString("preferences", comment: "")) {
            NavigationLink(destination: LazyView { AppearanceSettingsView() }) {
                Label(NSLocalizedString("appearance", comment: ""), systemImage: "paintbrush")
            }

            NavigationLink(destination: LazyView { LanguageSettingsView() }) {
                HStack {
                    Label(NSLocalizedString("language", comment: ""), systemImage: "globe")
                    Spacer()
                    Text(LocalizationManager.shared.isUsingAutomaticLanguage() ? NSLocalizedString("automatic", comment: "") : LocalizationManager.shared.getLanguageDisplayName(LocalizationManager.shared.getCurrentLanguage()))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }

            Toggle(isOn: Binding(
                get: { userSettings.smartTaskCreationEnabled },
                set: { userSettings.smartTaskCreationEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("smart_task_creations", comment: "Smart Task Creation"))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Text(NSLocalizedString("smart_task_creation_description", comment: "Parse dates, priorities, hashtags from titles"))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
        }
    }
}

/// Contacts section — only re-renders when ContactsService publishes
private struct SettingsContactsSection: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject private var contactsService = ContactsService.shared

    var body: some View {
        Section {
            if contactsService.authorizationStatus == .authorized || contactsService.authorizationStatus == .limited {
                HStack {
                    Label(NSLocalizedString("contacts.synced_contacts", comment: ""), systemImage: "person.crop.circle")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Spacer()
                    Text("\(contactsService.contactCount)")
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }

                if let lastSync = contactsService.lastSyncDate {
                    HStack {
                        Label(NSLocalizedString("last_sync", comment: ""), systemImage: "clock")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        Spacer()
                        Text(lastSync, style: .relative)
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                }

                Button {
                    _Concurrency.Task { _ = try? await contactsService.syncContacts() }
                } label: {
                    HStack {
                        Label(NSLocalizedString("contacts.sync_contacts_now", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(Theme.accent)
                        Spacer()
                        if contactsService.isSyncing {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
                .disabled(contactsService.isSyncing)

                if contactsService.authorizationStatus == .limited {
                    Button { openContactsSettings() } label: {
                        HStack {
                            Label(NSLocalizedString("contacts.grant_full_access", comment: ""), systemImage: "person.crop.circle.badge.plus")
                                .foregroundColor(Theme.accent)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    }
                }
            } else if contactsService.authorizationStatus == .denied {
                Button { openContactsSettings() } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("contacts.access_required", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("contacts.open_settings_prompt", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button { requestContactsAccess() } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("contacts.add_collaborators", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("contacts.upload_for_collaboration", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                Text(NSLocalizedString("contacts", comment: ""))
            }
        } footer: {
            Text(NSLocalizedString("contacts.footer_text", comment: ""))
                .font(Theme.Typography.caption2())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                contactsService.checkAuthorizationStatus()
                if contactsService.hasPermission && contactsService.contactCount == 0 {
                    _Concurrency.Task {
                        await contactsService.fetchContactStatus()
                        if contactsService.contactCount == 0 {
                            _ = try? await contactsService.syncContacts()
                        }
                    }
                }
            }
        }
    }

    private func requestContactsAccess() {
        _Concurrency.Task {
            let granted = await contactsService.requestAccess()
            if granted { _ = try? await contactsService.syncContacts() }
        }
    }

    private func openContactsSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager.shared)
}
