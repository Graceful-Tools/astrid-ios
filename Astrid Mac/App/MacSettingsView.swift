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
                Section(NSLocalizedString("appearance", comment: "")) {
                    Picker(NSLocalizedString("settings.appearance.theme", comment: ""), selection: $themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Section(NSLocalizedString("tasks.tasks", comment: "")) {
                    // Smart Task Creation — gates the shared SmartTaskParser in quick-add (a840511d).
                    Toggle(NSLocalizedString("smart_task_creations", comment: ""), isOn: Binding(
                        get: { userSettings.smartTaskCreationEnabled },
                        set: { userSettings.smartTaskCreationEnabled = $0 }
                    ))
                    Text(NSLocalizedString("mac.smart_parse_hint", comment: ""))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                    // Sub-tasks display (consumed by the list's subtask rendering, 3c945236).
                    Picker(NSLocalizedString("mac.subtasks", comment: ""), selection: Binding(
                        get: { userSettings.settings.subtaskDisplay ?? "indented" },
                        set: { userSettings.updateSettings(UserSettings(subtaskDisplay: $0)) }
                    )) {
                        Text(NSLocalizedString("settings.subtasks.indented", comment: "")).tag("indented")
                        Text(NSLocalizedString("settings.subtasks.under_parent", comment: "")).tag("under_parent")
                    }
                }
            }
            .formStyle(.grouped).macThemedSurface()
            .tabItem { Label(NSLocalizedString("mac.general", comment: ""), systemImage: "gearshape") }

            MacReminderSettingsView()
                .tabItem { Label(NSLocalizedString("reminders", comment: ""), systemImage: "bell") }

            MacSyncSettingsView()
                .tabItem { Label(NSLocalizedString("sync", comment: ""), systemImage: "arrow.triangle.2.circlepath") }

            MacAISettingsView()
                .tabItem { Label(NSLocalizedString("mac.ai", comment: ""), systemImage: "sparkles") }

            MacLanguageSettingsView()
                .tabItem { Label(NSLocalizedString("language", comment: ""), systemImage: "globe") }

            MacConnectionSettingsView()
                .tabItem { Label(NSLocalizedString("Connection", comment: ""), systemImage: "network") }

            MacAccountView()
                .tabItem { Label(NSLocalizedString("account", comment: ""), systemImage: "person.circle") }
        }
        .frame(width: 500, height: 380)
    }
}
#endif
