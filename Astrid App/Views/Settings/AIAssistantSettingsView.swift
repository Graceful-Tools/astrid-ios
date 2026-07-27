import SwiftUI

/**
 * Exploratory Features Settings View
 *
 * Provides access to alpha/experimental features:
 * - AI Assistants (API Key management)
 * - Apple Reminders sync
 */
struct AIAssistantSettingsView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Form {
            // Astrid's AI — top of the page
            Section(header: Text("\(Brand.appName)'s AI")) {
                NavigationLink(destination: DefaultAgentPickerView()) {
                    HStack {
                        Image("AstridCharacter")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Brand.appName)'s AI")
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text("Choose which AI model powers \(Brand.appName)")
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            // AI Assistants Section (API Keys + OpenClaw)
            Section(header: Text(NSLocalizedString("ai_assistants", comment: ""))) {
                NavigationLink(destination: AIAPIKeyManagerView()) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.ai.manage_keys", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("settings.ai.manage_keys_subtitle", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }

                NavigationLink(destination: OpenClawSettingsView()) {
                    HStack {
                        Image("ai-openclaw")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.openclaw.title", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("settings.openclaw.subtitle", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            // Apple Reminders Section
            Section(header: Text(NSLocalizedString("apple_reminders", comment: ""))) {
                NavigationLink(destination: AppleRemindersSettingsView()) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.reminders.configure_sync", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("settings.reminders.sync_subtitle", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }

            // Alpha Warning
            Section(footer: Text(NSLocalizedString("settings.exploratory.warning", comment: ""))) {
                EmptyView()
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackgroundPrimary()
        .navigationTitle(NSLocalizedString("exploratory_features", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .swipeToDismiss()
    }
}

#Preview {
    NavigationStack {
        AIAssistantSettingsView()
    }
}
