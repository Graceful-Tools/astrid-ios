import XCTest
@testable import Astrid_App

@MainActor
/// A manager on this test's own defaults suite (`DefaultsTestCase`): the language override and
/// `AppleLanguages` it writes stay out of the test process's real defaults (AITD-534).
final class LanguageSettingsTests: DefaultsTestCase {
    /// Stateless apart from its defaults, so a fresh one on this test's suite each time is the same
    /// manager — and needs no main-actor setUp override.
    var localizationManager: LocalizationManager { LocalizationManager(defaults: defaults) }
    let testOverrideKey = "user_language_override"

    // MARK: - Language Settings Tests

    func testSetLanguageUpdatesUserDefaults() {
        // Test that setting a language updates UserDefaults correctly
        localizationManager.setLanguage("es")

        let storedLanguage = defaults.string(forKey: testOverrideKey)
        XCTAssertEqual(storedLanguage, "es", "Setting language should store it in UserDefaults")
    }

    func testClearOverrideRemovesPreference() {
        // Test that clearing override removes the preference
        localizationManager.setLanguage("fr")
        XCTAssertNotNil(defaults.string(forKey: testOverrideKey))

        localizationManager.clearLanguageOverride()

        let storedLanguage = defaults.string(forKey: testOverrideKey)
        XCTAssertNil(storedLanguage, "Clearing override should remove the preference from UserDefaults")
    }

    func testGetCurrentLanguageWithoutOverride() {
        // Test that getCurrentLanguage returns correct value without override
        // Should return a supported language based on device locale
        let currentLanguage = localizationManager.getCurrentLanguage()

        XCTAssertTrue(Constants.Localization.supportedLanguages.contains(currentLanguage),
                     "getCurrentLanguage should return a supported language code")
    }

    func testGetCurrentLanguageWithOverride() {
        // Test that getCurrentLanguage returns correct value with override
        localizationManager.setLanguage("es")

        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "es",
                      "getCurrentLanguage should return the overridden language")
    }

    func testIsUsingAutomaticLanguageWithoutOverride() {
        // Test that isUsingAutomaticLanguage returns true without override
        localizationManager.clearLanguageOverride()

        let isAutomatic = localizationManager.isUsingAutomaticLanguage()
        XCTAssertTrue(isAutomatic,
                     "isUsingAutomaticLanguage should return true when no override is set")
    }

    func testIsUsingAutomaticLanguageWithOverride() {
        // Test that isUsingAutomaticLanguage returns false with override
        localizationManager.setLanguage("fr")

        let isAutomatic = localizationManager.isUsingAutomaticLanguage()
        XCTAssertFalse(isAutomatic,
                      "isUsingAutomaticLanguage should return false when override is set")
    }

    func testGetLanguageDisplayNameEnglish() {
        // Test display name helper for English
        let displayName = localizationManager.getLanguageDisplayName("en")

        // The key's own translation — and a resolved one, not the key echoed back (AITD-536)
        XCTAssertEqual(displayName, NSLocalizedString("english", comment: ""))
        XCTAssertNotEqual(displayName, "english", "unresolved key")
    }

    func testGetLanguageDisplayNameSpanish() {
        // Test display name helper for Spanish
        let displayName = localizationManager.getLanguageDisplayName("es")

        // The key's own translation — and a resolved one, not the key echoed back (AITD-536)
        XCTAssertEqual(displayName, NSLocalizedString("spanish", comment: ""))
        XCTAssertNotEqual(displayName, "spanish", "unresolved key")
    }

    func testGetLanguageDisplayNameFrench() {
        // Test display name helper for French
        let displayName = localizationManager.getLanguageDisplayName("fr")

        // The key's own translation — and a resolved one, not the key echoed back (AITD-536)
        XCTAssertEqual(displayName, NSLocalizedString("french", comment: ""))
        XCTAssertNotEqual(displayName, "french", "unresolved key")
    }

    func testGetLanguageDisplayNameUnsupportedLanguage() {
        // Test display name helper for unsupported language code
        // Note: "de" is now supported, so use a truly unsupported code like "xx"
        let displayName = localizationManager.getLanguageDisplayName("xx")

        XCTAssertEqual(displayName, "XX",
                      "Unsupported language should return uppercase code")
    }

    // MARK: - Language Settings State Tests

    func testLanguageSelectionPersistsAcrossSessions() {
        // Test that language selection persists
        localizationManager.setLanguage("es")

        // Simulate app restart by getting a fresh instance
        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "es",
                      "Language selection should persist across sessions")
    }

    func testSwitchingBetweenLanguages() {
        // Test switching between different languages
        localizationManager.setLanguage("en")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "en")

        localizationManager.setLanguage("es")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "es")

        localizationManager.setLanguage("fr")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "fr")
    }

    func testRevertingToAutomatic() {
        // Test reverting from manual selection to automatic
        localizationManager.setLanguage("es")
        XCTAssertFalse(localizationManager.isUsingAutomaticLanguage())

        localizationManager.clearLanguageOverride()
        XCTAssertTrue(localizationManager.isUsingAutomaticLanguage())
    }

    // MARK: - Integration Tests

    func testCompleteLanguageSettingsFlow() {
        // Test a complete user flow:
        // 1. User starts with automatic
        // 2. Selects Spanish manually
        // 3. Switches to French
        // 4. Reverts to automatic

        // Start with automatic
        localizationManager.clearLanguageOverride()
        XCTAssertTrue(localizationManager.isUsingAutomaticLanguage())

        // Select Spanish
        localizationManager.setLanguage("es")
        XCTAssertFalse(localizationManager.isUsingAutomaticLanguage())
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "es")

        // Switch to French
        localizationManager.setLanguage("fr")
        XCTAssertFalse(localizationManager.isUsingAutomaticLanguage())
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "fr")

        // Revert to automatic
        localizationManager.clearLanguageOverride()
        XCTAssertTrue(localizationManager.isUsingAutomaticLanguage())
        XCTAssertTrue(Constants.Localization.supportedLanguages.contains(
            localizationManager.getCurrentLanguage()
        ))
    }

    // MARK: - Edge Cases

    func testSetLanguageWithEmptyString() {
        // Test that setting an empty string doesn't crash
        localizationManager.setLanguage("")

        let storedLanguage = defaults.string(forKey: testOverrideKey)
        XCTAssertNil(storedLanguage, "Empty string should not be stored")
    }

    func testSetLanguageWithUppercaseCode() {
        // Test that uppercase language codes are handled (should be rejected as unsupported)
        localizationManager.setLanguage("ES")

        let storedLanguage = defaults.string(forKey: testOverrideKey)
        XCTAssertNil(storedLanguage, "Uppercase language code should not be stored")
    }

    func testMultipleClearOverrideCalls() {
        // Test that multiple calls to clearLanguageOverride don't cause issues
        localizationManager.setLanguage("es")
        localizationManager.clearLanguageOverride()

        XCTAssertNoThrow(localizationManager.clearLanguageOverride(),
                        "Multiple clear calls should not throw")
        XCTAssertTrue(localizationManager.isUsingAutomaticLanguage())
    }
}
