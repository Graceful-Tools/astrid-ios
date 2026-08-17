import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    // iPad layout settings (per-device, not synced)
    @AppStorage("iPadLandscapeColumns") private var landscapeColumns: Int = 3
    @AppStorage("iPadPortraitMode") private var portraitMode: String = "twoColumn"

    // Task-detail layout (task 96727335). Synced, not @AppStorage — it is a server preference.
    @StateObject private var userSettings = UserSettingsService.shared
    @ObservedObject private var featureFlags = FeatureFlagService.shared

    /// Reads through `TaskDisplayMode` so null and anything unrecognised resolve to `.list`,
    /// and writes only the two literals the server accepts — anything else is a 400.
    ///
    /// The setter refuses until settings have actually loaded. Without that, opening this screen
    /// before the fetch returns and touching the control would write the DEFAULT over whatever
    /// the user had chosen — the trap called out on task 8ef7d89d, which the picker is also
    /// disabled for, so the guard is belt and braces rather than the only defence.
    private var taskDisplayModeBinding: Binding<TaskDisplayMode> {
        Binding(
            get: { TaskDisplayMode(stored: userSettings.settings.taskDisplayMode) },
            set: { newMode in
                guard TaskDisplayMode.mayPersistSelection(
                    hasLoadedSettings: userSettings.hasLoadedFromServer) else { return }
                userSettings.updateSettings(UserSettings(taskDisplayMode: newMode.wireValue))
            }
        )
    }

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header
                FloatingTextHeader(NSLocalizedString("appearance", comment: ""), icon: "paintbrush", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                // Content
                Form {
                    Section(header: Text(NSLocalizedString("settings.appearance.theme", comment: ""))) {
                Picker(NSLocalizedString("appearance", comment: ""), selection: $themeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Offered only where the "project" layout means something — that is what Jon asked
            // for ("for people who have the projects feature flipper turned on"). Note this
            // gates the CONTROL, not the preference: `taskDisplayMode` is honoured whatever the
            // flag says, because access and preference are different questions (task 8ef7d89d).
            if featureFlags.isEnabled(.projectMode) {
                Section(header: Text(NSLocalizedString("settings.appearance.task_details", comment: "")),
                        footer: Text(NSLocalizedString("settings.appearance.task_details_footer", comment: ""))) {
                    Picker(NSLocalizedString("settings.appearance.task_details", comment: ""),
                           selection: taskDisplayModeBinding) {
                        Text(NSLocalizedString("settings.task_display.list", comment: "")).tag(TaskDisplayMode.list)
                        Text(NSLocalizedString("settings.task_display.project", comment: "")).tag(TaskDisplayMode.project)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!TaskDisplayMode.mayPersistSelection(
                        hasLoadedSettings: userSettings.hasLoadedFromServer))
                    .accessibilityIdentifier("settings.taskDisplayMode")
                }
            }

            Section(header: Text(NSLocalizedString("settings.appearance.email_to_task", comment: "")), footer: Text(NSLocalizedString("settings.appearance.email_to_task_footer", comment: ""))) {
                VStack(alignment: .leading, spacing: Theme.spacing12) {
                    HStack(spacing: Theme.spacing8) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Theme.accent)
                        Text(Brand.inboundTaskEmail)
                            .font(Theme.Typography.body())
                            .fontWeight(.medium)
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("settings.appearance.email_to_task_self", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("settings.appearance.email_to_task_assigned", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("settings.appearance.email_to_task_group", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        Divider()
                            .padding(.vertical, Theme.spacing4)

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(.purple)
                            Text(NSLocalizedString("settings.appearance.email_to_task_subject", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(.purple)
                            Text(NSLocalizedString("settings.appearance.email_to_task_body", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                    }
                }
                .padding(.vertical, Theme.spacing8)
            }

                    // iPad Layout section (only shown on iPad)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Section(header: Text(NSLocalizedString("settings.appearance.ipad_layout", comment: "iPad Layout"))) {
                            Picker(NSLocalizedString("settings.appearance.landscape_layout", comment: "Landscape"), selection: $landscapeColumns) {
                                Text(NSLocalizedString("settings.appearance.three_columns", comment: "3 Columns")).tag(3)
                                Text(NSLocalizedString("settings.appearance.two_columns", comment: "2 Columns")).tag(2)
                            }

                            Picker(NSLocalizedString("settings.appearance.portrait_layout", comment: "Portrait"), selection: $portraitMode) {
                                Text(NSLocalizedString("settings.appearance.two_columns", comment: "2 Columns")).tag("twoColumn")
                                Text(NSLocalizedString("settings.appearance.single_column", comment: "Single Column")).tag("iPhone")
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
    }
}


#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
