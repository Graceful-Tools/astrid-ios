//  MacSettingsView.swift
//  Astrid for Mac — native Settings scene (⌘,) wired to the shared settings services (M1).
//
//  Reuses the shared, UserDefaults-first settings model (works offline; syncs when online).

#if os(macOS)
import SwiftUI

struct MacSettingsView: View {
    @StateObject private var reminders = ReminderSettings.shared
    @StateObject private var userSettings = UserSettingsService.shared
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
                Section("Tasks") {
                    // Smart Task Creation — gates the shared SmartTaskParser in quick-add (a840511d).
                    Toggle("Smart Task Creation", isOn: Binding(
                        get: { userSettings.smartTaskCreationEnabled },
                        set: { userSettings.smartTaskCreationEnabled = $0 }
                    ))
                    Text("Parse dates, priorities, and #lists from what you type.")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                    // Sub-tasks display (consumed by the list's subtask rendering, 3c945236).
                    Picker("Sub-tasks", selection: Binding(
                        get: { userSettings.settings.subtaskDisplay ?? "indented" },
                        set: { userSettings.updateSettings(UserSettings(subtaskDisplay: $0)) }
                    )) {
                        Text("In lists, indented").tag("indented")
                        Text("Inside parent task only").tag("under_parent")
                    }
                }
            }
            .formStyle(.grouped).macThemedSurface()
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
