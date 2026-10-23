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

        let selectedLanguage = LanguageSelection.best(
            preferredLanguages: preferredLanguages,
            regionCode: currentLocale.region?.identifier
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

        return LanguageSelection.best(preferredLanguages: Locale.preferredLanguages, regionCode: nil)
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

/// Which shipped localization a device's language settings ask for. Pure, so the rule is
/// tested directly rather than through `UserDefaults` and the simulator's own locale.
enum LanguageSelection {
    /// The first supported preferred language — unless the region has an affinity with a
    /// supported language the user also listed (a US-English user in Mexico who lists
    /// Spanish gets Spanish). The region never adds a language the user did not list.
    /// English when nothing matches.
    static func best(preferredLanguages: [String], regionCode: String?) -> String {
        var priority: [String] = []
        for identifier in preferredLanguages {
            if let code = supportedLanguage(from: identifier), !priority.contains(code) {
                priority.append(code)
            }
        }
        if let affinity = regionCode.flatMap(languageAffinity(forRegion:)), priority.contains(affinity) {
            return affinity
        }
        return priority.first ?? "en"
    }

    /// The shipped localization a preferred-language identifier names ("es-MX" → "es"), or nil.
    static func supportedLanguage(from identifier: String) -> String? {
        let parts = identifier.components(separatedBy: CharacterSet(charactersIn: "-_"))
        guard let language = parts.first?.lowercased() else { return nil }
        let code = language == "zh" ? chineseScript(parts.dropFirst().map { $0.uppercased() }) : language
        return Constants.Localization.supportedLanguages.contains(code) ? code : nil
    }

    /// Chinese ships per script: an explicit script decides, else the region's.
    private static func chineseScript(_ subtags: [String]) -> String {
        if subtags.contains("HANT") { return "zh-Hant" }
        if subtags.contains("HANS") { return "zh-Hans" }
        return subtags.contains(where: ["TW", "HK", "MO"].contains) ? "zh-Hant" : "zh-Hans"
    }

    private static func languageAffinity(forRegion regionCode: String) -> String? {
        let region = regionCode.uppercased()
        if Constants.Localization.spanishSpeakingRegions.contains(region) { return "es" }
        if Constants.Localization.frenchSpeakingRegions.contains(region) { return "fr" }
        return nil
    }
}
