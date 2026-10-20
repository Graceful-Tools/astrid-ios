import XCTest
@testable import Astrid_App

/// AITD-512: user-facing copy that named Astrid outright, so a partner build said "A new
/// Astrid is ready" and posted an unlocalized "Task Due Soon".
final class WhitelabelCopyTests: XCTestCase {

    private let localizations = ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"]

    private func strings(_ language: String) throws -> [String: String] {
        let path = "Astrid App/Resources/Localizations/\(language).lproj/Localizable.strings"
        let data = Data(try RepositoryLocator.source(at: path).utf8)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String], path)
    }

    /// The update card takes the app's name as an argument rather than spelling it out.
    func testUpdateTitleTakesTheBrandName_AITD512() throws {
        for language in localizations {
            let title = try XCTUnwrap(try strings(language)["update.available_title"], language)
            XCTAssertFalse(title.contains("Astrid"), "\(language): \(title)")
            XCTAssertTrue(title.contains("%@"), "\(language): \(title)")
        }
        // An Astrid build still reads exactly as before.
        XCTAssertEqual(String(format: try XCTUnwrap(try strings("en")["update.available_title"]), Brand.appName),
                       "A new Astrid is ready")
    }

    /// The due-soon reminder title is localized, in every language the app ships.
    func testDueSoonTitleIsLocalized_AITD512() throws {
        for language in localizations {
            XCTAssertNotNil(try strings(language)["notifications.due_soon_title"], "\(language) lacks notifications.due_soon_title")
        }
        XCTAssertEqual(NSLocalizedString("notifications.due_soon_title", comment: ""), "Task Due Soon")
        let source = try RepositoryLocator.source(at: "Astrid App/Core/Notifications/NotificationManager.swift")
        XCTAssertFalse(source.contains("\"Task Due Soon\""), "NotificationManager still hardcodes the due-soon title")
    }
}
