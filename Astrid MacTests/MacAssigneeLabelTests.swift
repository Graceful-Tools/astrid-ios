//  MacAssigneeLabelTests.swift
//  What the Mac calls an unassigned task (task 6c891bce).
//
//  Jon: "assignment picker has 'no one' for unassigned. It should be consistent with web and
//  iOS." Both of those say **Unassigned** — iOS through the `assignee.unassigned` key, web as
//  the literal in `user-picker.tsx`. Only the Mac said "No one".
//
//  It was worse than a wording difference. `NSLocalizedString("No one", comment: "")` uses the
//  English text AS the key, and there is no "No one" entry in Localizable.strings — so every
//  one of the twelve translations fell back to English. The Mac was not merely inconsistent,
//  it was unlocalized.
//
//  User-facing copy is a cross-platform contract (ASTRID.md rule 8, and the Web-i18n ⇄
//  iOS-Localizable.strings registry in astrid-web's PRODUCT_CONTRACT.md). Diverging is a bug on
//  whichever platform moved, and the Mac is the one that moved.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAssigneeLabelTests: XCTestCase {

    /// The shared key iOS already uses. Naming it once here is the point of the test.
    private let sharedKey = "assignee.unassigned"

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - The bug

    /// An unassigned option reads the same word as iOS and web.
    func testUnassignedReadsTheSameAsEveryOtherPlatform() {
        let option = MacAssigneeOption(userId: nil, user: nil, isCurrentUser: false)
        XCTAssertEqual(option.displayName, NSLocalizedString(sharedKey, comment: ""))
    }

    /// And that is a real translated string, not the English text standing in as its own key.
    /// This is the half that made twelve languages read "No one".
    func testTheLabelIsALocalizedKeyRatherThanEnglishText() {
        let resolved = NSLocalizedString(sharedKey, comment: "")
        XCTAssertNotEqual(resolved, sharedKey,
                          "assignee.unassigned is missing from Localizable.strings")
        XCTAssertEqual(resolved, "Unassigned")
    }

    /// The literal must not come back anywhere in the Mac's assignee UI — it is what this task
    /// is about, and it reappears easily because it reads perfectly fine in English.
    func testNoMacAssigneeSurfaceStillSaysNoOne() throws {
        for path in ["Astrid Mac/Views/MacAssigneeOptions.swift",
                     "Astrid Mac/Views/MacAssigneePicker.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("NSLocalizedString(\"No one\""),
                           "\(path) still uses the English text as its own key")
        }
    }

    // MARK: - One definition, not two

    /// The picker used to spell the fallback itself instead of asking the option for its name,
    /// which is how the two drifted from iOS separately. One definition means one thing to fix
    /// next time.
    func testThePickerAsksTheOptionForItsLabel() throws {
        let picker = try source("Astrid Mac/Views/MacAssigneePicker.swift")
        XCTAssertTrue(picker.contains("MacAssigneeOption.unassignedLabel"),
                      "The picker should use the shared label, not re-derive one")
    }

    /// A real user's name is untouched by any of this.
    func testAnAssignedOptionStillShowsTheirName() {
        let user = User(id: "u1", email: "a@b.c", name: "Ada Lovelace", image: nil)
        let option = MacAssigneeOption(userId: "u1", user: user, isCurrentUser: false)
        XCTAssertEqual(option.displayName, user.displayName)
    }
}
#endif
