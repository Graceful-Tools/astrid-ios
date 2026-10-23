//  UITestStrings.swift
//  What the app shows for a key, for the few assertions that read a STATE out of a label.
//
//  A control is found by its accessibility identifier, never by its words (AITD-526). But some
//  state only exists as words — the date chip says "No due date" or a date — and an identifier
//  that changed with the state would be a second, test-only copy of it. So those assertions read
//  the app's own `en.lproj` table by key: `UITestLaunch.makeApp` launches in English whatever the
//  simulator is set to, so this is the copy on screen, and a wording change follows the key
//  instead of failing a test that spelled the old wording out.
//
//  Read from the checkout rather than the app bundle, which the runner cannot see. The runner is
//  on the same Mac as the tree, the way `RepositoryLocator` relies on for the unit suites.

import Foundation

enum UITestStrings {

    /// The English copy for `key`. Stops the run if the table or the key is missing: falling back
    /// to the key itself would turn a moved file into a confusing assertion failure much later.
    static func en(_ key: String) -> String {
        guard let value = table[key] else {
            fatalError("No \"\(key)\" in \(tablePath) — the app's en.lproj moved or the key was renamed")
        }
        return value
    }

    private static let tablePath: String = {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Astrid App.xcodeproj").path) { break }
        }
        return url.appendingPathComponent("Astrid App/Resources/Localizations/en.lproj/Localizable.strings").path
    }()

    private static let table: [String: String] =
        NSDictionary(contentsOfFile: tablePath) as? [String: String] ?? [:]
}
