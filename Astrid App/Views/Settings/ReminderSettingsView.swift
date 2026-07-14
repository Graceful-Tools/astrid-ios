import SwiftUI
import UserNotifications
import Combine

struct ReminderSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var settings = ReminderSettings.shared
    @State private var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingReminderTest = false
    @State private var reminderTestError: String?

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header
                FloatingTextHeader(NSLocalizedString("reminders", comment: ""), icon: "bell", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                // Content
                Form {
                    Section(header: Text(NSLocalizedString("settings.reminders.push_notifications", comment: ""))) {
                Toggle(NSLocalizedString("settings.reminders.enable_push", comment: ""), isOn: $settings.pushEnabled)
                    .onChange(of: settings.pushEnabled) { oldValue, newValue in
                        if newValue {
                            _Concurrency.Task { await requestNotificationPermission() }
                        }
                    }
                    .tint(Theme.accent)

                if notificationPermissionStatus == .denied {
                    Button(NSLocalizedString("settings.reminders.open_settings", comment: "")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(Theme.accent)
                }
            }

            Section(header: Text(NSLocalizedString("settings.reminders.email_notifications", comment: ""))) {
                Toggle(NSLocalizedString("settings.reminders.send_email", comment: ""), isOn: $settings.emailEnabled)
                    .onChange(of: settings.emailEnabled) { oldValue, newValue in
                        _Concurrency.Task { await settings.save() }
                    }
                    .tint(Theme.accent)
            }

            Section(header: Text(NSLocalizedString("settings.reminders.default_time", comment: ""))) {
                Picker(NSLocalizedString("settings.reminders.when_to_remind", comment: ""), selection: $settings.defaultReminderOffset) {
                    ForEach(ReminderOffset.allCases, id: \.self) { offset in
                        Text(offset.displayName).tag(offset)
                    }
                }
                .onChange(of: settings.defaultReminderOffset) { oldValue, newValue in
                    _Concurrency.Task { await settings.save() }
                }
            }

            Section(header: Text(NSLocalizedString("settings.reminders.daily_digest", comment: ""))) {
                Toggle(NSLocalizedString("settings.reminders.send_daily_digest", comment: ""), isOn: $settings.dailyDigestEnabled)
                    .tint(Theme.accent)

                if settings.dailyDigestEnabled {
                    DatePicker(NSLocalizedString("settings.reminders.digest_time", comment: ""),
                              selection: $settings.dailyDigestTime,
                              displayedComponents: .hourAndMinute)

                    Picker(NSLocalizedString("settings.reminders.timezone", comment: ""), selection: $settings.timezone) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { tz in
                            Text(tz).tag(tz)
                        }
                    }
                }
            }

            Section(header: Text(NSLocalizedString("settings.reminders.quiet_hours", comment: ""))) {
                Toggle(NSLocalizedString("settings.reminders.enable_quiet_hours", comment: ""), isOn: $settings.quietHoursEnabled)
                    .tint(Theme.accent)

                if settings.quietHoursEnabled {
                    DatePicker(NSLocalizedString("settings.reminders.start", comment: ""),
                              selection: $settings.quietHoursStart,
                              displayedComponents: .hourAndMinute)
                    DatePicker(NSLocalizedString("settings.reminders.end", comment: ""),
                              selection: $settings.quietHoursEnd,
                              displayedComponents: .hourAndMinute)
                }
            }

            Section(header: Text(NSLocalizedString("settings.reminders.test", comment: ""))) {
                Button {
                    _Concurrency.Task {
                        await testReminder()
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundColor(Theme.accent)
                        Text(NSLocalizedString("settings.reminders.send_test", comment: ""))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                }
                .alert(NSLocalizedString("settings.reminders.test_reminder", comment: ""), isPresented: $showingReminderTest) {
                    Button(NSLocalizedString("actions.done", comment: "")) { }
                } message: {
                    if let error = reminderTestError {
                        Text(error)
                    } else {
                        Text(NSLocalizedString("settings.reminders.test_message", comment: ""))
                    }
                }
            }
                }

                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
        .task {
            await checkNotificationPermission()
        }
        .onAppear {
            // Fetch latest settings from server when screen appears
            _Concurrency.Task {
                await settings.fetch()
            }
        }
        .refreshable {
            // Pull to refresh - force fetch
            await settings.fetch(force: true)
        }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings.pushEnabled = granted
            await checkNotificationPermission()
            await settings.save()
        } catch {
            print("Failed to request notification permission: \(error)")
        }
    }

    private func checkNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        notificationPermissionStatus = notificationSettings.authorizationStatus
    }

    private func testReminder() async {
        reminderTestError = nil

        do {
            try await NotificationManager.shared.scheduleTestReminder()
            showingReminderTest = true
        } catch {
            reminderTestError = error.localizedDescription
            showingReminderTest = true
            print("❌ Failed to schedule test reminder: \(error)")
        }
    }
}


#Preview {
    NavigationStack {
        ReminderSettingsView()
    }
}
