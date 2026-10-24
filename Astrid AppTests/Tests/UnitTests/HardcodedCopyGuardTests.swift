//  HardcodedCopyGuardTests.swift
//  Guards for AITD-403 — user-facing copy that was English-only while its key already existed.
//
//  CLAUDE.md rule 8: never hardcode user-facing copy. The screens below each said a word that
//  `Localizable.strings` already carried in twelve languages, so a Spanish user got "Cancel",
//  and the Mac's list defaults said "Today" where iOS said whatever `time.today` translates to —
//  the same list, two languages, depending on which app you opened it in.
//
//  These assert the FIX rather than scanning for the pattern in general: a blanket
//  "no string literal in a Text()" sweep flags previews, wire values and format specifiers, and
//  a guard that cries wolf gets suppressed.

import XCTest
@testable import Astrid_App

final class HardcodedCopyGuardTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// THE ONE THAT MUST STAY ENGLISH. `createList(description:)` writes to the SERVER, so
    /// localizing it would store the creator's UI language in a field every other member reads —
    /// on other platforms, in a language they did not choose. A literal-matching scan cannot tell
    /// this apart from copy, which is exactly why it is pinned rather than left to judgement.
    func testAITD403_TheSmartListWireValueIsNotLocalized() throws {
        let src = try source("Astrid App/Views/Lists/SaveFilterDialog.swift")
        XCTAssertTrue(src.contains(#"description: "Smart List""#),
                      "AITD-403: this is a stored value, not copy — it must not become a key")
    }

    /// The Mac's list defaults showed English while iOS localized the same list. Values stay
    /// English because they are what `updateListAdvanced` stores; only labels are translated.
    func testAITD403_MacListDefaultsLocalizesLabelsButNotWireValues() throws {
        let src = try source("Astrid Mac/Views/MacListDefaults.swift")
        for key in ["time.today", "time.tomorrow", "time.next_week", "time.next_month",
                    "repeating.never", "repeating.daily"] {
            XCTAssertTrue(src.contains(key), "AITD-403: the Mac label should come from \(key)")
        }
        for wireValue in [#".init("today""#, #".init("tomorrow""#, #".init("never""#] {
            XCTAssertTrue(src.contains(wireValue),
                          "AITD-403: \(wireValue) is the stored value and stays English")
        }
    }

    /// A completed-task BADGE is not a "Done" BUTTON. `actions.done` is the imperative
    /// finish/dismiss label — German "Fertig" — where the badge means "this is completed",
    /// German "Erledigt". The AITD-403 scan matched them by their shared English word; mapping
    /// them onto one key would have shipped the wrong word in eleven languages.
    func testAITD403_TheCompletedBadgeUsesTheStatusKeyNotTheButtonKey() throws {
        let src = try source("Astrid App/Views/Components/AutocompleteSupport.swift")
        XCTAssertTrue(src.contains(#"NSLocalizedString("tasks.completed""#),
                      "AITD-403: the badge is a status, not a button")
        XCTAssertFalse(src.contains(#"NSLocalizedString("actions.done""#),
                       "AITD-403: actions.done is the button label and belongs in TaskTimerView")
        XCTAssertTrue(try source("Astrid App/Views/Tasks/TaskTimerView.swift")
                        .contains(#"NSLocalizedString("actions.done""#),
                      "AITD-403: that one IS a button")
    }
}
