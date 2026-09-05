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
            Section(NSLocalizedString("Notifications", comment: "")) {
                Toggle(NSLocalizedString("mac.push_reminders", comment: ""), isOn: $s.pushEnabled)
                Toggle(NSLocalizedString("mac.email_reminders", comment: ""), isOn: $s.emailEnabled)
                Picker(NSLocalizedString("mac.default_reminder", comment: ""), selection: $s.defaultReminderOffset) {
                    ForEach(ReminderOffset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section(NSLocalizedString("settings.reminders.daily_digest", comment: "")) {
                Toggle(NSLocalizedString("mac.enabled", comment: ""), isOn: $s.dailyDigestEnabled)
                if s.dailyDigestEnabled {
                    DatePicker(NSLocalizedString("mac.time", comment: ""), selection: $s.dailyDigestTime, displayedComponents: .hourAndMinute)
                }
            }
            Section(NSLocalizedString("settings.reminders.quiet_hours", comment: "")) {
                Toggle(NSLocalizedString("mac.enabled", comment: ""), isOn: $s.quietHoursEnabled)
                if s.quietHoursEnabled {
                    DatePicker(NSLocalizedString("mac.from", comment: ""), selection: $s.quietHoursStart, displayedComponents: .hourAndMinute)
                    DatePicker(NSLocalizedString("mac.to", comment: ""), selection: $s.quietHoursEnd, displayedComponents: .hourAndMinute)
                }
            }
        }
        .formStyle(.grouped).macThemedSurface()
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
            Section(NSLocalizedString("language", comment: "")) {
                Picker(NSLocalizedString("mac.app_language", comment: ""), selection: $language) {
                    ForEach(codes, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code).tag(code)
                    }
                }
                .onChange(of: language) { LocalizationManager.shared.setLanguage(language) }
                Text(NSLocalizedString("mac.relaunch_note", comment: ""))
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }
        }
        .formStyle(.grouped).macThemedSurface()
    }
}

// MARK: - Connection

struct MacConnectionSettingsView: View {
    @StateObject private var conn = ConnectionModeManager.shared

    var body: some View {
        Form {
            Section(NSLocalizedString("Connection", comment: "")) {
                LabeledContent("Mode", value: conn.currentMode.displayName)
                LabeledContent("Server", value: Constants.API.baseURL)
            }
        }
        .formStyle(.grouped).macThemedSurface()
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
    @State private var connecting: String?          // provider whose connection we're polling for

    var body: some View {
        Form {
            // Google Tasks is behind a remote rollout / kill switch (Task b0048881) —
            // hide it entirely when the flag is off, matching iOS SettingsView.
            if featureFlags.isEnabled(.googleTasks) {
                providerSection("Google Tasks", connected: google.isConnected, account: google.accountEmail,
                                lastSync: google.lastSyncedAt, isConnecting: connecting == "Google Tasks",
                                connect: {
                                    // In-app auth session auto-returns on the callback (task 6745f40f) —
                                    // no external browser / status polling needed.
                                    connecting = "Google Tasks"
                                    defer { connecting = nil }
                                    do { try await google.connect() }
                                    catch is CancellationError {}
                                    catch { MacErrorCenter.shared.report("Connect Google Tasks", error) }
                                },
                                disconnect: { await google.disconnect() },
                                refresh: { await google.refreshStatus() },
                                manage: { showGoogleLinks = true })
            }
            providerSection("GitHub Issues", connected: github.isConnected, account: github.accountLogin,
                            lastSync: github.lastSyncedAt, isConnecting: connecting == "GitHub Issues",
                            connect: {
                                if let u = await github.authorizeURL() { PlatformApplication.open(u) }
                                await pollConnection("GitHub Issues", refresh: { await github.refreshStatus() },
                                                     isConnected: { github.isConnected })
                            },
                            disconnect: { await github.disconnect() },
                            refresh: { await github.refreshStatus() },
                            manage: { showGitHubLinks = true })
            Section(NSLocalizedString("apple_reminders", comment: "")) {
                HStack {
                    Circle().fill(MacRemindersStatus.isGranted(apple.authorizationStatus) ? Theme.success : Theme.textMuted)
                        .frame(width: 8, height: 8)
                    Text(MacRemindersStatus.label(apple.authorizationStatus)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button(NSLocalizedString("mac.manage", comment: "")) { showReminders = true }
                }
                if apple.linkedListCount > 0 { LabeledContent("Linked lists", value: "\(apple.linkedListCount)") }
                if let d = apple.lastSyncDate { LabeledContent("Last sync") { Text(d, style: .relative) } }
            }
        }
        .formStyle(.grouped).macThemedSurface()
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

    /// After opening the OAuth browser, poll the provider's status until it connects (macOS has no
    /// in-app callback) so the UI updates automatically instead of needing a close/reopen.
    private func pollConnection(_ title: String, refresh: @escaping () async -> Void,
                                isConnected: @escaping () -> Bool) async {
        connecting = title
        defer { connecting = nil }
        var attempt = 0
        while MacConnectPoll.shouldContinue(attempt: attempt, connected: isConnected()) {
            try? await _Concurrency.Task.sleep(nanoseconds: MacConnectPoll.intervalNanos)
            await refresh()
            attempt += 1
        }
    }

    @ViewBuilder
    private func providerSection(_ title: String, connected: Bool, account: String?, lastSync: Date?,
                                 isConnecting: Bool = false,
                                 connect: @escaping () async -> Void,
                                 disconnect: @escaping () async -> Void,
                                 refresh: (() async -> Void)? = nil,
                                 manage: (() -> Void)? = nil) -> some View {
        Section(title) {
            HStack {
                Circle().fill(connected ? Theme.success : Theme.textMuted).frame(width: 8, height: 8)
                Text(connected ? (account ?? "Connected")
                     : isConnecting ? "Connecting…" : "Not connected").foregroundStyle(Theme.textPrimary)
                if isConnecting { ProgressView().controlSize(.small) }
                Spacer()
                if connected {
                    Button(NSLocalizedString("sync.disconnect", comment: ""), role: .destructive) { _Concurrency.Task { await disconnect() } }
                } else {
                    // Manual re-check in case the browser round-trip already finished.
                    if let refresh {
                        Button { _Concurrency.Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help(NSLocalizedString("mac.refresh_connection", comment: ""))
                    }
                    Button(NSLocalizedString("mac.connect", comment: "")) { _Concurrency.Task { await connect() } }.disabled(isConnecting)
                }
            }
            if connected, let manage {
                Button(NSLocalizedString("mac.manage_links", comment: "")) { manage() }
            }
            if let d = lastSync { LabeledContent("Last sync") { Text(d, style: .relative) } }
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
            Text(NSLocalizedString("mac.browse_public_lists", comment: "")).font(.headline).foregroundStyle(Theme.textPrimary)
            TextField(NSLocalizedString("actions.search", comment: ""), text: $query).textFieldStyle(.roundedBorder)
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
                        Label(NSLocalizedString("mac.added", comment: ""), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    } else if copyingId == l.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(NSLocalizedString("actions.add", comment: "")) { copy(l) }
                    }
                }
            }
            .frame(minHeight: 260)
            HStack { Spacer(); Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return, modifiers: []) }
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
