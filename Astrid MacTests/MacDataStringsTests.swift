//  MacDataStringsTests.swift
//  Regression tests for Task 29b673c0 — "[mac] localize all Mac only strings into supported
//  languages".
//
//  Every `mac.*` key was already translated in all 12 languages. What was still English was the
//  text that never passed through a view builder at all — it lived in DATA: repeat units and
//  member roles rendered with `.capitalized`, command-palette entries, copy destinations,
//  onboarding copy, and the ⌘/ sheet's row titles (which come from the cross-platform shortcut
//  table and stay English there by design). A literal-scanning guard cannot see any of it.

import XCTest
@testable import Astrid_Mac

final class MacDataStringsTests: XCTestCase {

    private static let languages = ["en", "es", "fr", "de", "it", "ja",
                                    "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"]

    // MARK: rendered-from-data labels

    /// The custom-repeat picker showed "days"/"weeks" capitalized — English in every language.
    func testRepeatUnitsAreLocalized() {
        for unit in MacCustomRepeat.units {
            let title = MacRepeatUnitLabel.title(for: unit)
            XCTAssertFalse(title.isEmpty)
            XCTAssertFalse(title.hasPrefix("repeating."), "\(unit) shows an unresolved key")
        }
        // Reuses the iOS keys so both apps say the same thing.
        XCTAssertEqual(MacRepeatUnitLabel.title(for: "days"), NSLocalizedString("repeating.days", comment: ""))
    }

    /// The member-role pickers showed "member"/"admin" capitalized.
    func testMemberRolesAreLocalized() {
        XCTAssertEqual(MacMemberRoleLabel.title(for: "member"), NSLocalizedString("lists.member_role", comment: ""))
        XCTAssertEqual(MacMemberRoleLabel.title(for: "admin"), NSLocalizedString("lists.admin", comment: ""))
        XCTAssertEqual(MacMemberRoleLabel.title(for: "owner"), NSLocalizedString("lists.owner", comment: ""))
    }

    /// An unknown value still renders something readable rather than an empty row.
    func testUnknownValuesFallBackToTheRawWord() {
        XCTAssertEqual(MacRepeatUnitLabel.title(for: "fortnights"), "Fortnights")
        XCTAssertEqual(MacMemberRoleLabel.title(for: "guest"), "Guest")
    }

    /// The copy-to-list menu's first entry was a hardcoded "My Tasks only".
    func testCopyTargetsAreLocalized() {
        let label = MacTaskCopy.targets(lists: []).first?.label
        XCTAssertEqual(label, NSLocalizedString("mac.my_tasks_only", comment: ""))
        XCTAssertNotEqual(label, "mac.my_tasks_only")
    }

    // MARK: the ⌘/ sheet

    /// Every row of the shortcuts sheet has a translation — the sheet was fully English because
    /// its titles come from the shared web-parity table.
    func testEveryShortcutRowHasALocalizedTitle() {
        for action in ShortcutAction.allCases {
            let title = MacShortcutTitle.localized(for: action)
            XCTAssertFalse(title.isEmpty)
            XCTAssertNotEqual(title, "mac.shortcut.\(action.rawValue)",
                              "\(action.rawValue) has no translation")
        }
    }

    /// …in every language, not just English.
    func testShortcutTitlesTranslateInEveryLanguage() throws {
        for lang in Self.languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for action in ShortcutAction.allCases {
                let key = "mac.shortcut.\(action.rawValue)"
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key,
                                  "\(lang) is missing \(key)")
            }
        }
    }

    /// The shared table keeps its English titles on purpose — they mirror web's handler names and
    /// are part of the cross-platform contract, so translating them in place would break parity.
    func testTheSharedTableStaysEnglish() {
        XCTAssertEqual(KeyboardShortcuts.all.first(where: { $0.action == .newTask })?.title, "New task")
    }

    // MARK: onboarding + palette

    func testOnboardingAndPaletteKeysTranslateInEveryLanguage() throws {
        let keys = ["mac.onboard.quickadd.title", "mac.onboard.quickadd.detail",
                    "mac.onboard.palette.title", "mac.onboard.palette.detail",
                    "mac.onboard.keyboard.title", "mac.onboard.keyboard.detail",
                    "mac.onboard.offline.title", "mac.onboard.offline.detail",
                    "mac.refresh_lists", "mac.my_tasks_only",
                    "mac.edit_comment", "mac.rename_subtask"]
        for lang in Self.languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key,
                                  "\(lang) is missing \(key)")
            }
        }
    }

    /// The command palette lists the commands by name — those names were English constants.
    @MainActor
    func testPaletteCommandsAreLocalized() {
        let titles = MacAppModel.shared.registry.commands.map(\.title)
        XCTAssertTrue(titles.contains(NSLocalizedString("tasks.new_task", comment: "")))
        XCTAssertTrue(titles.contains(NSLocalizedString("mac.refresh_lists", comment: "")))
    }
}

/// The write-failure banner (Task 29b673c0) — it showed the English call-site context verbatim.
final class MacFailureCopyTests: XCTestCase {

    private static let languages = ["en", "es", "fr", "de", "it", "ja",
                                    "ko", "nl", "pt", "ru", "zh-Hans", "zh-Hant"]

    /// Every real call-site context maps to a translated sentence — never to the raw English.
    func testEveryCallSiteContextMapsToATranslation() {
        let contexts = ["Complete task", "Complete tasks", "Complete subtask", "Add task",
                        "Add subtask", "Add to Astrid", "Create share link", "Register agent",
                        "Invite jon@example.com", "Post comment", "Attach file", "Link Reminders",
                        "Delete list", "Delete tasks", "Delete comment", "Remove member",
                        "Save notes", "Save due date", "Update assignee", "Update list privacy",
                        "Rename task", "Change role", "Set priority", "Reorder tasks", "Move task",
                        "Make subtask", "Share task", "Export data", "Test API key"]
        for context in contexts {
            let message = MacFailureCopy.message(for: context)
            XCTAssertFalse(message.isEmpty, "\(context) has no banner copy")
            XCTAssertFalse(message.hasPrefix("mac.failed."), "\(context) shows an unresolved key")
            XCTAssertNotEqual(message, context, "\(context) leaks the developer string to the user")
        }
    }

    /// Grouped by verb: deletes read as deletes, creates as creates.
    func testTheVerbPicksTheCategory() {
        XCTAssertEqual(MacFailureCopy.message(for: "Delete list"),
                       NSLocalizedString("mac.failed.delete", comment: ""))
        XCTAssertEqual(MacFailureCopy.message(for: "Remove member"),
                       NSLocalizedString("mac.failed.delete", comment: ""))
        XCTAssertEqual(MacFailureCopy.message(for: "Add subtask"),
                       NSLocalizedString("mac.failed.create", comment: ""))
        XCTAssertEqual(MacFailureCopy.message(for: "Save notes"),
                       NSLocalizedString("mac.failed.save", comment: ""))
        XCTAssertEqual(MacFailureCopy.message(for: "Complete task"),
                       NSLocalizedString("mac.failed.complete", comment: ""))
    }

    /// An unrecognised verb still gets a translated line rather than falling back to English.
    func testUnknownVerbsGetTheGenericLine() {
        XCTAssertEqual(MacFailureCopy.message(for: "Frobnicate widget"),
                       NSLocalizedString("mac.failed.generic", comment: ""))
        XCTAssertEqual(MacFailureCopy.message(for: ""),
                       NSLocalizedString("mac.failed.generic", comment: ""))
    }

    func testEveryLanguageTranslatesTheBannerCopy() throws {
        for lang in Self.languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["mac.failed.save", "mac.failed.create", "mac.failed.delete",
                        "mac.failed.complete", "mac.failed.generic"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key,
                                  "\(lang) is missing \(key)")
            }
        }
    }
}
