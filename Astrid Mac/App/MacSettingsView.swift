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

            MacReminderSettingsView()
                .tabItem { Label("Reminders", systemImage: "bell") }

            MacSyncSettingsView()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

            MacAISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }

            MacLanguageSettingsView()
                .tabItem { Label("Language", systemImage: "globe") }

            MacConnectionSettingsView()
                .tabItem { Label("Connection", systemImage: "network") }

            MacAccountView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 500, height: 380)
    }
}
#endif
