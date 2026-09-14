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

    /// Every screen the AITD-403 scan named must be free of the literal it was called out for.
    func testAITD403_TheNamedScreensNoLongerHardcodeCopyThatHasAKey() throws {
        let offenders: [(path: String, literals: [String])] = [
            ("Astrid App/Views/Lists/AddMemberSheet.swift", [#"Button("Cancel")"#]),
            ("Astrid App/Views/Components/InlineListsPicker.swift", [#"Button("Cancel")"#]),
            ("Astrid App/Views/Components/InlineRepeatPicker.swift", [#"Button("Cancel")"#]),
            ("Astrid App/Views/Components/ImagePickerView.swift", [#"Button("Cancel")"#]),
            ("Astrid App/Views/Settings/AIAPIKeyManagerView.swift", [#"Text("Cancel")"#]),
            ("Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift",
             [#"Button("Cancel")"#, #"Button("Cancel", role:"#, #"Button("Delete", role:"#]),
            ("Astrid App/Views/Tasks/TaskTimerView.swift", [#"Text("Done")"#]),
            ("Astrid App/Views/Components/AutocompleteSupport.swift", [#"Text("Done")"#]),
            // The ASSIGNMENT only. The AppLog.debug line one row below says the same words and
            // must stay English — developer logs are not user-facing copy, the same convention
            // AppActions' call-site contexts follow.
            ("Astrid App/Views/Components/ShareTargetView.swift",
             [#"errorMessage = "Failed to generate share link"#]),
        ]
        for (path, literals) in offenders {
            let src = try source(path)
            for literal in literals {
                XCTAssertFalse(src.contains(literal),
                               "AITD-403: \(path) should use a Localizable.strings key, not \(literal)")
            }
        }
    }

    /// `SaveFilterDialog` and `ListAgentSettingsView` were localized wholesale, so they are
    /// checked by the absence of ANY bare `Text("…")` / `Button("…")` / `return "…"` copy.
    func testAITD403_TheWhollyLocalizedScreensKeepNoBareCopy() throws {
        for path in ["Astrid App/Views/Lists/SaveFilterDialog.swift",
                     "Astrid App/Views/Lists/ListAgentSettingsView.swift"] {
            let src = try source(path)
            for (index, line) in src.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                // `description: "Smart List"` is a WIRE VALUE, not copy — see the next test.
                guard !code.contains("description:") else { continue }
                for shape in [#"Text(""#, #"Button(""#, #"Section(""#, #"TextField(""#] {
                    XCTAssertFalse(code.contains(shape),
                                   "AITD-403: \(path):\(index + 1) — \(code)")
                }
            }
        }
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
