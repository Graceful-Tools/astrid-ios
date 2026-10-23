import XCTest
@testable import Astrid_App

@MainActor
final class LocalizationManagerTests: XCTestCase {
    var localizationManager: LocalizationManager!
    let testOverrideKey = "user_language_override"

    override func setUpWithError() throws {
        try super.setUpWithError()
        localizationManager = LocalizationManager.shared
        // Clear any existing overrides before each test
        UserDefaults.standard.removeObject(forKey: testOverrideKey)
        UserDefaults.standard.synchronize()
    }

    override func tearDownWithError() throws {
        // Clean up after tests
        UserDefaults.standard.removeObject(forKey: testOverrideKey)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        try super.tearDownWithError()
    }

    // MARK: - Language Code Extraction Tests

    /// A preferred-language identifier resolves to the localization the app ships, or none (AITD-538).
    func testSupportedLanguageFromIdentifier() {
        let testCases: [(input: String, expected: String?)] = [
            ("en", "en"),
            ("es", "es"),
            ("en-US", "en"),
            ("es-MX", "es"),
            ("fr-CA", "fr"),
            ("en_US", "en"),
            ("es_ES", "es"),
            ("ar", nil),
            ("ar-SA", nil),
        ]
        for testCase in testCases {
            XCTAssertEqual(LanguageSelection.supportedLanguage(from: testCase.input), testCase.expected, testCase.input)
        }
    }

    /// Chinese reached the app as "zh", which is not a localization it ships — Chinese users
    /// got English. The script decides, and a bare region picks the script it writes (AITD-538).
    func testChineseResolvesToItsScript() {
        let testCases: [(input: String, expected: String)] = [
            ("zh-Hans-CN", "zh-Hans"),
            ("zh-Hans", "zh-Hans"),
            ("zh-Hant-TW", "zh-Hant"),
            ("zh-Hant-HK", "zh-Hant"),
            ("zh_Hant", "zh-Hant"),
            ("zh-TW", "zh-Hant"),
            ("zh-HK", "zh-Hant"),
            ("zh-MO", "zh-Hant"),
            ("zh-CN", "zh-Hans"),
            ("zh-SG", "zh-Hans"),
            ("zh", "zh-Hans"),
        ]
        for testCase in testCases {
            XCTAssertEqual(LanguageSelection.supportedLanguage(from: testCase.input), testCase.expected, testCase.input)
        }
    }

    // MARK: - Best Language (region affinity)

    func testBestLanguageIsTheFirstSupportedPreference() {
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["ar-SA", "de-DE", "en-US"], regionCode: "DE"), "de")
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["zh-Hant-TW", "en-US"], regionCode: "TW"), "zh-Hant")
    }

    /// A US user who lists Spanish second, living in Mexico, gets Spanish: the region lifts a
    /// supported language the user already listed.
    func testRegionAffinityLiftsAListedLanguage() {
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["en-US", "es-MX"], regionCode: "MX"), "es")
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["en-CA", "fr-CA"], regionCode: "ca"), "fr")
    }

    /// The region never imposes a language the user did not list.
    func testRegionAffinityNeverAddsALanguage() {
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["en-US"], regionCode: "MX"), "en")
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["en-GB", "es-ES"], regionCode: "GB"), "en")
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["en-US", "es-US"], regionCode: nil), "en")
    }

    func testBestLanguageFallsBackToEnglish() {
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: ["ar-SA", "he-IL"], regionCode: "SA"), "en")
        XCTAssertEqual(LanguageSelection.best(preferredLanguages: [], regionCode: nil), "en")
    }

    // MARK: - Language Override Tests

    func testSetLanguageStoresOverride() {
        // When user manually selects a language, it should be stored
        localizationManager.setLanguage("es")

        let storedLanguage = UserDefaults.standard.string(forKey: testOverrideKey)
        XCTAssertEqual(storedLanguage, "es", "Language override should be stored in UserDefaults")
    }

    func testSetLanguageRejectsUnsupportedLanguage() {
        // Should reject unsupported language codes
        localizationManager.setLanguage("ar") // Arabic not supported

        let storedLanguage = UserDefaults.standard.string(forKey: testOverrideKey)
        XCTAssertNil(storedLanguage, "Unsupported language should not be stored")
    }

    func testClearLanguageOverride() {
        // Set an override, then clear it
        localizationManager.setLanguage("es")
        XCTAssertNotNil(UserDefaults.standard.string(forKey: testOverrideKey))

        localizationManager.clearLanguageOverride()
        XCTAssertNil(UserDefaults.standard.string(forKey: testOverrideKey),
                    "Language override should be cleared")
    }

    func testGetCurrentLanguageReturnsOverride() {
        // When override is set, getCurrentLanguage should return it
        localizationManager.setLanguage("fr")

        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "fr", "Should return the user override")
    }

    // MARK: - Supported Languages Tests

    func testSupportedLanguagesContainsExpectedLanguages() {
        // Verify all expected languages are supported
        let expectedLanguages = ["en", "es", "fr"]

        for lang in expectedLanguages {
            XCTAssertTrue(Constants.Localization.supportedLanguages.contains(lang),
                         "\(lang) should be in supported languages")
        }
    }

    // MARK: - Integration Tests

    func testApplyLanguageSetsAppleLanguages() {
        // Test that applying a language sets the AppleLanguages preference
        localizationManager.setLanguage("es")

        if let appleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] {
            XCTAssertEqual(appleLanguages.first, "es",
                         "AppleLanguages should be set to the selected language")
        } else {
            XCTFail("AppleLanguages should be set in UserDefaults")
        }
    }

    func testApplyIntelligentLocaleWithoutOverride() {
        // Test that applyIntelligentLocale works without crashing
        // This is an integration test that verifies the full flow
        XCTAssertNoThrow(localizationManager.applyIntelligentLocale(),
                        "applyIntelligentLocale should not throw")

        // Verify that AppleLanguages was set
        let appleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        XCTAssertNotNil(appleLanguages, "AppleLanguages should be set")
        XCTAssertFalse(appleLanguages?.isEmpty ?? true, "AppleLanguages should not be empty")
    }

    func testApplyIntelligentLocaleRespectsOverride() {
        // When user has set an override, it should be respected
        localizationManager.setLanguage("fr")

        localizationManager.applyIntelligentLocale()

        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "fr",
                      "Should respect user override even after applyIntelligentLocale")
    }

    // MARK: - Edge Case Tests

    func testGetCurrentLanguageFallsBackToEnglish() {
        // When no override and no matching preferred languages, should default to English
        // This is hard to test directly without mocking Locale.preferredLanguages,
        // but we can verify the logic exists
        let currentLanguage = localizationManager.getCurrentLanguage()

        // Should return one of our supported languages
        XCTAssertTrue(Constants.Localization.supportedLanguages.contains(currentLanguage),
                     "Should return a supported language")
    }

    func testMultipleSetLanguageCalls() {
        // Test that multiple calls to setLanguage work correctly
        localizationManager.setLanguage("es")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "es")

        localizationManager.setLanguage("fr")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "fr")

        localizationManager.setLanguage("en")
        XCTAssertEqual(localizationManager.getCurrentLanguage(), "en")
    }

    // MARK: - Real-World Scenario Tests

    func testUSSpanishUserScenario() {
        // Scenario: US user (region=US) who speaks Spanish (es-US locale or es in preferred languages)
        // They should get Spanish, not English

        // Simulate by setting Spanish as override (in real app, this would be detected from locale)
        localizationManager.setLanguage("es")

        let currentLanguage = localizationManager.getCurrentLanguage()
        XCTAssertEqual(currentLanguage, "es",
                      "US user with Spanish preferences should get Spanish")
    }

    // MARK: - Constants Validation Tests

    func testUserLanguageOverrideKeyIsConsistent() {
        // Verify the constant is defined and matches what we use in tests
        XCTAssertEqual(Constants.Localization.userLanguageOverrideKey, testOverrideKey,
                      "Test key should match constant")
    }
}
