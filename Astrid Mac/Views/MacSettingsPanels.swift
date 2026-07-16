//  MacSettingsPanels.swift
//  Astrid for Mac — settings panels over the shared services (gap closure):
//  full reminders, language, sync providers, connection. Native Mac forms.

#if os(macOS)
import SwiftUI
import EventKit

// MARK: - Reminders (full)

struct MacReminderSettingsView: View {
    @StateObject private var s = ReminderSettings.shared

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Push reminders", isOn: $s.pushEnabled)
                Toggle("Email reminders", isOn: $s.emailEnabled)
                Picker("Default reminder", selection: $s.defaultReminderOffset) {
                    ForEach(ReminderOffset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("Daily digest") {
                Toggle("Enabled", isOn: $s.dailyDigestEnabled)
                if s.dailyDigestEnabled {
                    DatePicker("Time", selection: $s.dailyDigestTime, displayedComponents: .hourAndMinute)
                }
            }
            Section("Quiet hours") {
                Toggle("Enabled", isOn: $s.quietHoursEnabled)
                if s.quietHoursEnabled {
                    DatePicker("From", selection: $s.quietHoursStart, displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: $s.quietHoursEnd, displayedComponents: .hourAndMinute)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: s.pushEnabled) { save() }
        .onChange(of: s.emailEnabled) { save() }
        .onChange(of: s.defaultReminderOffset) { save() }
        .onChange(of: s.dailyDigestEnabled) { save() }
        .onChange(of: s.dailyDigestTime) { save() }
        .onChange(of: s.quietHoursEnabled) { save() }
        .onChange(of: s.quietHoursStart) { save() }
        .onChange(of: s.quietHoursEnd) { save() }
    }
    private func save() { _Concurrency.Task { await s.save() } }
}

// MARK: - Language

struct MacLanguageSettingsView: View {
    @State private var language = LocalizationManager.shared.getCurrentLanguage()

    private var codes: [String] { Constants.Localization.supportedLanguages }

    var body: some View {
        Form {
            Section("Language") {
                Picker("App language", selection: $language) {
                    ForEach(codes, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code).tag(code)
                    }
                }
                .onChange(of: language) { LocalizationManager.shared.setLanguage(language) }
                Text("Some changes take effect after relaunch.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Connection

struct MacConnectionSettingsView: View {
    @StateObject private var conn = ConnectionModeManager.shared

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Mode", value: conn.currentMode.displayName)
                LabeledContent("Server", value: Constants.API.baseURL)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sync providers

struct MacSyncSettingsView: View {
    @StateObject private var github = GitHubSyncService.shared
    @StateObject private var google = GoogleTasksSyncService.shared
    @StateObject private var apple = AppleRemindersService.shared
    @StateObject private var featureFlags = FeatureFlagService.shared

    var body: some View {
        Form {
            // Google Tasks is behind a remote rollout / kill switch (Task b0048881) —
            // hide it entirely when the flag is off, matching iOS SettingsView.
            if featureFlags.isEnabled(.googleTasks) {
                providerSection("Google Tasks", connected: google.isConnected, account: google.accountEmail,
                                lastSync: google.lastSyncedAt,
                                connect: { if let u = await google.authorizeURL() { PlatformApplication.open(u) } },
                                disconnect: { await google.disconnect() })
            }
            providerSection("GitHub Issues", connected: github.isConnected, account: github.accountLogin,
                            lastSync: github.lastSyncedAt,
                            connect: { if let u = await github.authorizeURL() { PlatformApplication.open(u) } },
                            disconnect: { await github.disconnect() })
            Section("Apple Reminders") {
                LabeledContent("Access", value: apple.authorizationStatus == .fullAccess ? "Granted" : "Not granted")
                if apple.linkedListCount > 0 { LabeledContent("Linked lists", value: "\(apple.linkedListCount)") }
                if let d = apple.lastSyncDate { LabeledContent("Last sync") { Text(d, style: .relative) } }
            }
        }
        .formStyle(.grouped)
        .task {
            await featureFlags.refreshIfStale()
            await github.refreshStatus()
            if featureFlags.isEnabled(.googleTasks) { await google.refreshStatus() }
        }
    }

    @ViewBuilder
    private func providerSection(_ title: String, connected: Bool, account: String?, lastSync: Date?,
                                 connect: @escaping () async -> Void,
                                 disconnect: @escaping () async -> Void) -> some View {
        Section(title) {
            HStack {
                Circle().fill(connected ? Theme.success : Theme.textMuted).frame(width: 8, height: 8)
                Text(connected ? (account ?? "Connected") : "Not connected").foregroundStyle(Theme.textPrimary)
                Spacer()
                if connected {
                    Button("Disconnect", role: .destructive) { _Concurrency.Task { await disconnect() } }
                } else {
                    Button("Connect") { _Concurrency.Task { await connect() } }
                }
            }
            if let d = lastSync { LabeledContent("Last sync") { Text(d, style: .relative) } }
        }
    }
}

// MARK: - AI

struct MacAISettingsView: View {
    @State private var settings: AIAssistantSettings?

    var body: some View {
        Form {
            Section("AI Assistant") {
                if let s = settings {
                    LabeledContent("Preferred service", value: s.preferredService ?? "Default")
                    LabeledContent("Default agent", value: s.defaultAgentId ?? "None")
                    LabeledContent("On-device model", value: s.isOnDeviceModel ? "Yes" : "No")
                } else {
                    Text("Loading…").foregroundStyle(Theme.textMuted)
                }
            }
        }
        .formStyle(.grouped)
        .task { settings = try? await ChatService.shared.getAIAssistantSettings() }
    }
}

// MARK: - Public list browser

struct MacPublicListsView: View {
    @State private var lists: [PublicListData] = []
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [PublicListData] {
        query.isEmpty ? lists : lists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse Public Lists").font(.headline).foregroundStyle(Theme.textPrimary)
            TextField("Search", text: $query).textFieldStyle(.roundedBorder)
            List(filtered, id: \.id) { l in
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.name).foregroundStyle(Theme.textPrimary)
                    if let d = l.description, !d.isEmpty {
                        Text(d).font(.caption).foregroundStyle(Theme.textMuted).lineLimit(2)
                    }
                }
            }
            .frame(minHeight: 260)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.return, modifiers: []) }
        }
        .padding(20)
        .frame(width: 460)
        .task { lists = (try? await RemoteResourceService.shared.getPublicLists().lists) ?? [] }
    }
}
#endif
