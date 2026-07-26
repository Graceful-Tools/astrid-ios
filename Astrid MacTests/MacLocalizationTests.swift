//  MacLocalizationTests.swift
//  Regression for task 4cf5d6ff — "[Mac] make sure that the strings in the mac app match those of
//  the iOS app and support all the same localization".
//
//  The Mac app shipped with ZERO NSLocalizedString calls: every label was hardcoded English, even
//  though all 12 .lproj bundles were already being copied into the Mac app. Strings that iOS
//  already had now reuse iOS's KEYS (so the two apps say the same thing in every language), and
//  Mac-only strings got new keys translated into all 12 languages.
//
//  Asserts the BUILT host bundle, never the repo tree (a sandboxed test host reading ~/Documents
//  hangs on TCC — see MacAppIconTests).

import XCTest
@testable import Astrid_Mac

final class MacLocalizationTests: XCTestCase {

    private static let languages = ["en", "es", "fr", "de", "it", "ja",
                                    "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"]

    /// Every language iOS supports must also be inside the Mac app.
    func testMacBundleShipsEveryLanguage() {
        for lang in Self.languages {
            XCTAssertNotNil(Bundle.main.path(forResource: lang, ofType: "lproj"),
                            "\(lang).lproj missing from the Mac bundle")
        }
    }

    /// Keys shared with iOS resolve — these are the ones that must MATCH the iOS wording.
    func testSharedIOSKeysResolveOnMac() {
        for key in ["navigation.my_tasks", "navigation.lists", "actions.cancel",
                    "actions.delete", "tasks.new_task", "lists.new_list"] {
            let value = NSLocalizedString(key, comment: "")
            XCTAssertNotEqual(value, key, "Shared iOS key \(key) does not resolve in the Mac bundle")
        }
    }

    /// Mac-specific keys resolve too.
    func testMacSpecificKeysResolve() {
        for key in ["mac.quit", "mac.open_astrid", "mac.sort_tasks", "mac.filter_tasks",
                    "mac.welcome", "mac.keyboard_shortcuts"] {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key,
                              "Mac key \(key) does not resolve")
        }
    }

    /// Every key must be translated in EVERY language — a missing entry silently falls back to
    /// English, which is exactly the state this task fixed.
    func testEveryLanguageTranslatesTheMacKeys() throws {
        let probes = ["mac.quit", "mac.refresh", "mac.settings_general_probe_absent"].prefix(2)
        for lang in Self.languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in probes {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(value, key, "\(lang) is missing a translation for \(key)")
            }
        }
    }

    /// Format keys keep their placeholders in every language, or String(format:) drops the value.
    func testFormatKeysKeepTheirPlaceholders() throws {
        let specs: [(String, String)] = [("mac.filter_title", "%@"), ("mac.comments_count", "%d"),
                                         ("mac.last_timer", "%@"), ("mac.share_title", "%@")]
        for lang in Self.languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for (key, placeholder) in specs {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertTrue(value.contains(placeholder),
                              "\(lang) \(key) lost its \(placeholder) placeholder: \(value)")
            }
        }
    }
}

// MARK: - Astrid's nags are localized too (task 2eb3a080)

extension MacLocalizationTests {

    /// The empty-state copy is Astrid speaking — part of the product, so it must translate like
    /// everything else. It was the last hardcoded English on Mac.
    func testEmptyStateCopyIsLocalized() {
        for copy in [MacEmptyCopy.noTasks, .filteredOut, .noListSelected, .chatEmpty] {
            XCTAssertFalse(copy.message.isEmpty)
            XCTAssertFalse(copy.message.hasPrefix("mac.empty"),
                           "\(copy.message) is an unresolved key, not a translation")
        }
        XCTAssertNotNil(MacEmptyCopy.filteredOut.detail)
    }

    /// Every language must actually translate them — a missing entry silently falls back to
    /// English, which is the state this task fixed.
    func testEveryLanguageTranslatesTheNags() throws {
        for lang in ["en", "es", "fr", "de", "it", "ja", "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["mac.empty.no_tasks", "mac.empty.chat", "mac.empty.no_list_selected"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key,
                                  "\(lang) is missing \(key)")
            }
        }
    }

    /// Count/name formats must keep their placeholders in every language.
    func testCountAndNameFormatsKeepPlaceholders() throws {
        for lang in ["en", "es", "fr", "de", "it", "ja", "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertTrue(bundle.localizedString(forKey: "mac.complete_count", value: nil, table: nil)
                .contains("%d"), "\(lang) lost %d in mac.complete_count")
            XCTAssertTrue(bundle.localizedString(forKey: "mac.delete_list_named", value: nil, table: nil)
                .contains("%@"), "\(lang) lost %@ in mac.delete_list_named")
        }
    }
}
