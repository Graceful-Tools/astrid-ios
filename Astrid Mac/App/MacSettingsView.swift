//  MacSettingsView.swift
//  Astrid for Mac — native Settings scene (⌘,) wired to the shared settings services (M1).
//
//  Reuses the shared, UserDefaults-first settings model (works offline; syncs when online).

#if os(macOS)
import SwiftUI

struct MacSettingsView: View {
    @StateObject private var reminders = ReminderSettings.shared
    @StateObject private var userSettings = UserSettingsService.shared
    @ObservedObject private var featureFlags = FeatureFlagService.shared
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    // Scroll bars are hidden by default (task 01d8cfa1); this puts them back for anyone who
    // wants the system behaviour.
    @AppStorage(MacScrollBars.defaultsKey) private var showScrollBars = false

    var body: some View {
        TabView {
            Form {
                Section(NSLocalizedString("appearance", comment: "")) {
                    Picker(NSLocalizedString("settings.appearance.theme", comment: ""), selection: $themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Toggle(NSLocalizedString("mac.show_scroll_bars", comment: ""), isOn: $showScrollBars)
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

                    // Offered only where the "project" layout means something — Jon: "for people
                    // who have the projects feature flipper turned on". This gates the CONTROL,
                    // not the preference: taskDisplayMode is honoured whatever the flag says,
                    // because access and preference are different questions (task 8ef7d89d).
                    if featureFlags.isEnabled(.projectMode) {
                        Picker(NSLocalizedString("settings.appearance.task_details", comment: ""),
                               selection: Binding(
                            get: { TaskDisplayMode(stored: userSettings.settings.taskDisplayMode) },
                            // Refuses until settings have loaded, or opening this pane before the
                            // fetch returns and touching the control writes the DEFAULT over the
                            // user's choice — the trap on task 8ef7d89d.
                            set: { newMode in
                                guard TaskDisplayMode.mayPersistSelection(
                                    hasLoadedSettings: userSettings.hasLoadedFromServer) else { return }
                                userSettings.updateSettings(
                                    UserSettings(taskDisplayMode: newMode.wireValue))
                            }
                        )) {
                            Text(NSLocalizedString("settings.task_display.list", comment: "")).tag(TaskDisplayMode.list)
                            Text(NSLocalizedString("settings.task_display.project", comment: "")).tag(TaskDisplayMode.project)
                        }
                        .disabled(!TaskDisplayMode.mayPersistSelection(
                            hasLoadedSettings: userSettings.hasLoadedFromServer))
                        .accessibilityIdentifier("settings.taskDisplayMode")
                        Text(NSLocalizedString("settings.appearance.task_details_footer", comment: ""))
                            .font(.caption).foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .formStyle(.grouped).macThemedSurface()
            .tabItem { Label(NSLocalizedString("mac.general", comment: ""), systemImage: "gearshape") }

            MacReminderSettingsView()
                .tabItem { Label(NSLocalizedString("reminders", comment: ""), systemImage: "bell") }

            MacSyncSettingsView()
                .tabItem { Label(NSLocalizedString("sync", comment: ""), systemImage: "arrow.triangle.2.circlepath") }

            MacAgentHubView()
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
