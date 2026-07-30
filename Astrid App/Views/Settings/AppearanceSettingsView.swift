import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    // iPad layout settings (per-device, not synced)
    @AppStorage("iPadLandscapeColumns") private var landscapeColumns: Int = 3
    @AppStorage("iPadPortraitMode") private var portraitMode: String = "twoColumn"

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
