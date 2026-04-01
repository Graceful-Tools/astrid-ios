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
            // Header
            Section {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text(NSLocalizedString("exploratory_features", comment: ""))
                        .font(Theme.Typography.headline())
                    Spacer()
                    Text(NSLocalizedString("alpha", comment: ""))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.warning)
                        .cornerRadius(4)
                }
            }

            // AI Assistants Section
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
            }

            // OpenClaw Section (Self-Hosted AI)
            Section(header: Text(NSLocalizedString("settings.openclaw.section", comment: ""))) {
                NavigationLink(destination: OpenClawSettingsView()) {
                    HStack {
                        Text("🦞")
                            .font(.title3)
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

            // Default AI Agent Section
            Section(header: Text(NSLocalizedString("settings.default_agent.section", comment: "Default AI Agent"))) {
                NavigationLink(destination: DefaultAgentPickerView()) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.default_agent.title", comment: "Default Agent"))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("settings.default_agent.subtitle", comment: "Choose which AI agent responds in chat"))
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
    }
}

#Preview {
    NavigationStack {
        AIAssistantSettingsView()
    }
}
