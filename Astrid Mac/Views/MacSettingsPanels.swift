//  MacSettingsPanels.swift
//  Astrid for Mac — settings panels over the shared services (gap closure):
//  full reminders, language, sync providers, connection. Native Mac forms.

#if os(macOS)
import SwiftUI
import AppKit
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
    @State private var showReminders = false
    @State private var showGoogleLinks = false
    @State private var showGitHubLinks = false

    var body: some View {
        Form {
            // Google Tasks is behind a remote rollout / kill switch (Task b0048881) —
            // hide it entirely when the flag is off, matching iOS SettingsView.
            if featureFlags.isEnabled(.googleTasks) {
                providerSection("Google Tasks", connected: google.isConnected, account: google.accountEmail,
                                lastSync: google.lastSyncedAt,
                                connect: { if let u = await google.authorizeURL() { PlatformApplication.open(u) } },
                                disconnect: { await google.disconnect() },
                                manage: { showGoogleLinks = true })
            }
            providerSection("GitHub Issues", connected: github.isConnected, account: github.accountLogin,
                            lastSync: github.lastSyncedAt,
                            connect: { if let u = await github.authorizeURL() { PlatformApplication.open(u) } },
                            disconnect: { await github.disconnect() },
                            manage: { showGitHubLinks = true })
            Section("Apple Reminders") {
                HStack {
                    Circle().fill(MacRemindersStatus.isGranted(apple.authorizationStatus) ? Theme.success : Theme.textMuted)
                        .frame(width: 8, height: 8)
                    Text(MacRemindersStatus.label(apple.authorizationStatus)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Manage…") { showReminders = true }
                }
                if apple.linkedListCount > 0 { LabeledContent("Linked lists", value: "\(apple.linkedListCount)") }
                if let d = apple.lastSyncDate { LabeledContent("Last sync") { Text(d, style: .relative) } }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showReminders) { MacAppleRemindersView() }
        .sheet(isPresented: $showGoogleLinks) { MacGoogleTasksLinksView() }
        .sheet(isPresented: $showGitHubLinks) { MacGitHubLinksView() }
        .task {
            await featureFlags.refreshIfStale()
            await github.refreshStatus()
            if featureFlags.isEnabled(.googleTasks) { await google.refreshStatus() }
        }
        // OAuth completes in the system browser; there's no in-app callback on Mac. Re-poll
        // connection status whenever the app regains focus so a new connection appears (Task 75b82a1b).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            _Concurrency.Task {
                await github.refreshStatus()
                if featureFlags.isEnabled(.googleTasks) { await google.refreshStatus() }
            }
        }
    }

    @ViewBuilder
    private func providerSection(_ title: String, connected: Bool, account: String?, lastSync: Date?,
                                 connect: @escaping () async -> Void,
                                 disconnect: @escaping () async -> Void,
                                 manage: (() -> Void)? = nil) -> some View {
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
            if connected, let manage {
                Button("Manage links…") { manage() }
            }
            if let d = lastSync { LabeledContent("Last sync") { Text(d, style: .relative) } }
        }
    }
}

// MARK: - AI

struct MacAISettingsView: View {
    @State private var settings: AIAssistantSettings?
    @State private var agents: [AvailableAgent] = []
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var showKeys = false

    var body: some View {
        Form {
            Section("API Keys & Agents") {
                Button("Manage API keys & OpenClaw agents…") { showKeys = true }
            }
            Section("AI Assistant") {
                if let s = settings {
                    Picker("Default agent", selection: Binding(
                        get: { s.defaultAgentId ?? "" },
                        set: { newId in if !newId.isEmpty { save(agentId: newId) } }
                    )) {
                        if s.defaultAgentId == nil { Text("None").tag("") }
                        ForEach(agents) { a in
                            Text("\(a.name) · \(a.serviceDisplayName)").tag(a.id)
                        }
                    }
                    LabeledContent("On-device model", value: s.isOnDeviceModel ? "Yes" : "No")
                    if isSaving { ProgressView().controlSize(.small) }
                } else if loadFailed {
                    HStack {
                        Text("Couldn’t load AI settings.").foregroundStyle(Theme.error)
                        Spacer()
                        Button("Retry") { _Concurrency.Task { await load() } }
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showKeys) { MacAIKeysView() }
        .task { await load() }
    }

    private func load() async {
        loadFailed = false
        do {
            settings = try await ChatService.shared.getAIAssistantSettings()
            agents = (try? await ChatService.shared.fetchAvailableAgents()) ?? []
        } catch {
            loadFailed = true
        }
    }

    private func save(agentId: String) {
        guard !isSaving else { return }
        isSaving = true
        _Concurrency.Task {
            defer { isSaving = false }
            if let updated = try? await ChatService.shared.updateAIAssistantSettings(defaultAgentId: agentId) {
                settings = updated
            }
        }
    }
}

// MARK: - Public list browser

struct MacPublicListsView: View {
    @StateObject private var listService = ListService.shared
    @State private var lists: [PublicListData] = []
    @State private var query = ""
    @State private var copyingId: String?
    @State private var addedIds = Set<String>()
    @Environment(\.dismiss) private var dismiss

    private var filtered: [PublicListData] {
        query.isEmpty ? lists : lists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse Public Lists").font(.headline).foregroundStyle(Theme.textPrimary)
            TextField("Search", text: $query).textFieldStyle(.roundedBorder)
            List(filtered, id: \.id) { l in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.name).foregroundStyle(Theme.textPrimary)
                        if let d = l.description, !d.isEmpty {
                            Text(d).font(.caption).foregroundStyle(Theme.textMuted).lineLimit(2)
                        }
                    }
                    Spacer()
                    if addedIds.contains(l.id) {
                        Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    } else if copyingId == l.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { copy(l) }
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

    /// Copy a public list into the user's own lists (through the service layer), then refresh.
    private func copy(_ l: PublicListData) {
        guard copyingId == nil else { return }
        copyingId = l.id
        _Concurrency.Task {
            defer { copyingId = nil }
            if (try? await RemoteResourceService.shared.copyList(listId: l.id, includeTasks: true)) != nil {
                addedIds.insert(l.id)
                _ = try? await listService.fetchLists()
            }
        }
    }
}
#endif
