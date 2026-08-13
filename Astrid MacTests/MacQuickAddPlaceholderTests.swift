//  MacQuickAddPlaceholderTests.swift
//  Regression guard for Task 3a4b6b1c — "[mac] task input should be 'Add a task…' only. currently
//  there is tips that complicates the UI."
//
//  The tip was not a separate view that could be deleted; it was baked into the placeholder STRING
//  ("Add a task…  (try “Report friday #work urgent”)") in all twelve languages, so it appeared in
//  both the main add bar and the menu-bar quick entry.
//
//  This guards the CATEGORY rather than one file: every translation must stay a plain invitation.
//  A syntax tip in the field teaches the feature once and then clutters it forever, and the
//  explanation of what smart parsing does already lives in Settings (`mac.smart_parse_hint`).

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacQuickAddPlaceholderTests: XCTestCase {

    private static let key = "mac.quick_add_placeholder"

    /// Every `*.lproj/Localizable.strings` in the repo, so a language added later is covered too.
    private func localizationFiles() throws -> [(language: String, url: URL)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid App/Resources/Localizations")
        let dirs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        XCTAssertGreaterThanOrEqual(dirs.count, 12, "Expected the full set of localizations")
        return dirs.map { ($0.deletingPathExtension().lastPathComponent,
                           $0.appendingPathComponent("Localizable.strings")) }
    }

    private func placeholder(in url: URL) throws -> String? {
        let contents = try String(contentsOf: url, encoding: .utf8)
        for line in contents.components(separatedBy: .newlines)
        where line.hasPrefix("\"\(Self.key)\"") {
            guard let open = line.range(of: "= \""),
                  let close = line.range(of: "\";", options: .backwards) else { return nil }
            return String(line[open.upperBound..<close.lowerBound])
        }
        return nil
    }

    /// The bug: a parenthetical syntax example riding along inside the placeholder.
    func testNoLanguageAdvertisesSmartParseSyntaxInThePlaceholder() throws {
        for (language, url) in try localizationFiles() {
            let value = try XCTUnwrap(placeholder(in: url), "\(language) is missing \(Self.key)")

            for tipMarker in ["(", "（", "#"] {
                XCTAssertFalse(value.contains(tipMarker),
                               "\(language): the add field must be a plain invitation, but reads \"\(value)\" — "
                               + "syntax tips belong in Settings, not in the field the user types into")
            }
        }
    }

    /// …and it must not go plain by going EMPTY. It still has to invite a task.
    func testEveryLanguageStillInvitesATask() throws {
        for (language, url) in try localizationFiles() {
            let value = try XCTUnwrap(placeholder(in: url))
            XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language): the placeholder must still say something")
            XCTAssertLessThanOrEqual(value.count, 32,
                                     "\(language): \"\(value)\" is long enough to be carrying a tip again")
        }
    }

    /// English is the one we can assert exactly — it is what the task asked for verbatim.
    func testEnglishReadsAddATask() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Resources/Localizations/en.lproj/Localizable.strings")
        XCTAssertEqual(try placeholder(in: root), "Add a task…")
    }
}
#endif
