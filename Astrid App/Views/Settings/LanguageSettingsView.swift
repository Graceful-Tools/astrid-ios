import SwiftUI

struct LanguageSettingsView: View {
    @ThemedPalette private var palette
    @Environment(\.dismiss) var dismiss
    @State private var selectedLanguage: String
    @State private var isAutomatic: Bool

    init() {
        let manager = LocalizationManager.shared
        let currentLang = manager.getCurrentLanguage()
        _selectedLanguage = State(initialValue: currentLang)
        _isAutomatic = State(initialValue: manager.isUsingAutomaticLanguage())
    }

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header
                FloatingTextHeader(NSLocalizedString("language_settings", comment: ""), icon: "globe", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                // Content
                Form {
                    Section {
                        // Automatic option
                        Button {
                            isAutomatic = true
                            LocalizationManager.shared.clearLanguageOverride()
                            selectedLanguage = LocalizationManager.shared.getCurrentLanguage()
                            ServerLocaleSync.shared.languageChanged()  // emails follow (AITD-663)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("automatic", comment: ""))
                                        .font(Theme.Typography.body())
                                        .foregroundColor(palette.textPrimary)
                                    Text(NSLocalizedString("device_language", comment: ""))
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(palette.textSecondary)
                                }
                                Spacer()
                                if isAutomatic {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Supported Languages
                        ForEach(Constants.Localization.supportedLanguages, id: \.self) { languageCode in
                            Button {
                                isAutomatic = false
                                selectedLanguage = languageCode
                                LocalizationManager.shared.setLanguage(languageCode)
                                ServerLocaleSync.shared.languageChanged()  // emails follow (AITD-663)
                            } label: {
                                HStack {
                                    Text(LocalizationManager.shared.getLanguageDisplayName(languageCode))
                                        .font(Theme.Typography.body())
                                        .foregroundColor(palette.textPrimary)
                                    Spacer()
                                    if !isAutomatic && selectedLanguage == languageCode {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text(NSLocalizedString("language_restart_note", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(palette.textSecondary)
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
        LanguageSettingsView()
    }
}
