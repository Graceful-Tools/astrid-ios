import Foundation

/// Manages intelligent locale-based language selection for the app
/// Prioritizes language over region when selecting localizations
/// For example: US-ES (Spanish in US) should get ES-ES instead of US-EN
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    private init() {}

    // MARK: - Public Methods

    /// Applies intelligent locale selection based on device locale and available localizations
    /// Should be called during app initialization before any UI strings are loaded
    func applyIntelligentLocale() {
        AppLog.debug("🌍 [LocalizationManager] Starting intelligent locale selection...")

        // Check if user has manually overridden language selection
        if let userOverride = getUserLanguageOverride() {
            AppLog.debug("✅ [LocalizationManager] User has manually selected language: \(userOverride)")
            applyLanguage(userOverride)
            return
        }

        // Get device locale and preferred languages
        let currentLocale = Locale.current
        let preferredLanguages = Locale.preferredLanguages

        AppLog.debug("🌍 [LocalizationManager] Current locale: \(currentLocale.identifier)")
        AppLog.debug("🌍 [LocalizationManager] Preferred languages: \(preferredLanguages.prefix(3).joined(separator: ", "))")

        // Find best matching language
        let selectedLanguage = findBestMatchingLanguage(
            locale: currentLocale,
            preferredLanguages: preferredLanguages
        )

        AppLog.debug("✅ [LocalizationManager] Selected language: \(selectedLanguage)")
        applyLanguage(selectedLanguage)
    }

    /// Manually set the app language (called from Settings)
    /// - Parameter languageCode: ISO 639-1 language code (e.g., "en", "es", "fr")
    func setLanguage(_ languageCode: String) {
        guard Constants.Localization.supportedLanguages.contains(languageCode) else {
            AppLog.debug("⚠️ [LocalizationManager] Unsupported language code: \(languageCode)")
            return
        }

        AppLog.debug("🌍 [LocalizationManager] User manually selected language: \(languageCode)")
        UserDefaults.standard.set(languageCode, forKey: Constants.Localization.userLanguageOverrideKey)
        applyLanguage(languageCode)
    }

    /// Get the currently applied language code
    func getCurrentLanguage() -> String {
        if let userOverride = getUserLanguageOverride() {
            return userOverride
        }

        // Return the first preferred language that we support
        let preferredLanguages = Locale.preferredLanguages
        for langPref in preferredLanguages {
            let langCode = extractLanguageCode(from: langPref)
            if Constants.Localization.supportedLanguages.contains(langCode) {
                return langCode
            }
        }

        // Default to English
        return "en"
    }

    /// Clear user language override and revert to automatic selection
    func clearLanguageOverride() {
        AppLog.debug("🌍 [LocalizationManager] Clearing language override...")
        UserDefaults.standard.removeObject(forKey: Constants.Localization.userLanguageOverrideKey)
        applyIntelligentLocale()
    }

    /// Check if the user is using automatic language detection or has set a manual override
    func isUsingAutomaticLanguage() -> Bool {
        return getUserLanguageOverride() == nil
    }

    /// Get user-friendly display name for a language code
    /// - Parameter code: ISO 639-1 language code (e.g., "en", "es", "fr")
    /// - Returns: Localized display name (e.g., "English", "Español", "Français")
    func getLanguageDisplayName(_ code: String) -> String {
        switch code {
        case "en":
            return NSLocalizedString("english", comment: "")
        case "es":
            return NSLocalizedString("spanish", comment: "")
        case "fr":
            return NSLocalizedString("french", comment: "")
        case "de":
            return NSLocalizedString("german", comment: "")
        case "it":
            return NSLocalizedString("italian", comment: "")
        case "ja":
            return NSLocalizedString("japanese", comment: "")
        case "ko":
            return NSLocalizedString("korean", comment: "")
        case "nl":
            return NSLocalizedString("dutch", comment: "")
        case "pt":
            return NSLocalizedString("portuguese", comment: "")
        case "ru":
            return NSLocalizedString("russian", comment: "")
        case "zh-Hans":
            return NSLocalizedString("chinese_simplified", comment: "")
        case "zh-Hant":
            return NSLocalizedString("chinese_traditional", comment: "")
        default:
            return code.uppercased()
        }
    }

    // MARK: - Private Methods

    private func getUserLanguageOverride() -> String? {
        return UserDefaults.standard.string(forKey: Constants.Localization.userLanguageOverrideKey)
    }

    /// Find the best matching language based on locale and preferred languages
    private func findBestMatchingLanguage(
        locale: Locale,
        preferredLanguages: [String]
    ) -> String {
        // Strategy:
        // 1. Check primary preferred language against supported languages
        // 2. Check if user's region suggests a different primary language (e.g., US user with Spanish preferences)
        // 3. Check secondary preferred languages
        // 4. Fall back to English

        // Extract language codes from preferred languages
        var languagePriority: [String] = []

        for langPref in preferredLanguages {
            let langCode = extractLanguageCode(from: langPref)
            if Constants.Localization.supportedLanguages.contains(langCode) && !languagePriority.contains(langCode) {
                languagePriority.append(langCode)
            }
        }

        AppLog.debug("🌍 [LocalizationManager] Language priority from preferences: \(languagePriority)")

        // Check for language-region affinity
        // If user is in a Spanish-speaking region, prioritize Spanish
        if let regionCode = locale.region?.identifier {
            AppLog.debug("🌍 [LocalizationManager] User region: \(regionCode)")

            // Check if this region has strong affinity with any of our supported languages
            if let affinityLanguage = findLanguageAffinityForRegion(regionCode) {
                AppLog.debug("🌍 [LocalizationManager] Region \(regionCode) has affinity with \(affinityLanguage)")

                // If the affinity language is in preferred languages (even if not first), prioritize it
                if languagePriority.contains(affinityLanguage) {
                    AppLog.debug("✅ [LocalizationManager] Prioritizing \(affinityLanguage) based on region affinity")
                    return affinityLanguage
                }
            }
        }

        // Return first supported language from priority list
        if let firstSupported = languagePriority.first {
            return firstSupported
        }

        // Default to English
        AppLog.debug("🌍 [LocalizationManager] No matching language found, defaulting to English")
        return "en"
    }

    /// Extract language code from locale identifier (e.g., "en-US" -> "en", "es" -> "es")
    private func extractLanguageCode(from localeIdentifier: String) -> String {
        // Handle both "en-US" and "en_US" formats
        let components = localeIdentifier.components(separatedBy: CharacterSet(charactersIn: "-_"))
        return components.first?.lowercased() ?? localeIdentifier.lowercased()
    }

    /// Check if a region has strong affinity with a supported language
    private func findLanguageAffinityForRegion(_ regionCode: String) -> String? {
        let upperRegion = regionCode.uppercased()

        // Check Spanish-speaking regions
        if Constants.Localization.spanishSpeakingRegions.contains(upperRegion) {
            return "es"
        }

        // Check French-speaking regions
        if Constants.Localization.frenchSpeakingRegions.contains(upperRegion) {
            return "fr"
        }

        // No strong affinity found
        return nil
    }

    /// Apply the selected language to the app
    private func applyLanguage(_ languageCode: String) {
        AppLog.debug("🌍 [LocalizationManager] Applying language: \(languageCode)")

        // Set the AppleLanguages user default to override app language
        // This affects Bundle.main.localizedString lookups
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        AppLog.debug("✅ [LocalizationManager] Language applied: \(languageCode)")
        AppLog.debug("🌍 [LocalizationManager] Note: Some UI elements may require app restart to update")
    }
}
