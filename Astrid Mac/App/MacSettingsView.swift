//  MacSettingsView.swift
//  Astrid for Mac — native Settings scene (⌘,) wired to the shared settings services (M1).
//
//  Reuses the shared, UserDefaults-first settings model (works offline; syncs when online).

#if os(macOS)
import SwiftUI

struct MacSettingsView: View {
    @StateObject private var reminders = ReminderSettings.shared
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    var body: some View {
        TabView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Reminders") {
                    Toggle("Push reminders", isOn: $reminders.pushEnabled)
                    Toggle("Email reminders", isOn: $reminders.emailEnabled)
                    Toggle("Daily digest", isOn: $reminders.dailyDigestEnabled)
                    Toggle("Quiet hours", isOn: $reminders.quietHoursEnabled)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Reminders", systemImage: "bell") }

            MacAccountView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 480, height: 340)
        .onChange(of: reminders.pushEnabled) { persist() }
        .onChange(of: reminders.emailEnabled) { persist() }
        .onChange(of: reminders.dailyDigestEnabled) { persist() }
        .onChange(of: reminders.quietHoursEnabled) { persist() }
    }

    private func persist() {
        _Concurrency.Task { await reminders.save() }   // UserDefaults immediately, server in background
    }
}
#endif
