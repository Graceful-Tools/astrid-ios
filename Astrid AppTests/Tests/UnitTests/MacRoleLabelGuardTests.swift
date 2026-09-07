//  MacRoleLabelGuardTests.swift
//  Regression guard for AITD-323 — "[mac] List member role labels are English literals".
//
//  `MacListMembersView` rendered a member's role twice on the same screen and disagreed with
//  itself: the picker used the localized `MacMemberRoleLabel.title(for:)`, while the row beside
//  it read
//
//      Text(isOwner(m) ? "Owner" : m.role.capitalized)
//
//  which is English in all 12 languages twice over — a bare literal for the owner, and the raw
//  wire value (`"member"`, `"admin"`) capitalized for everyone else. `.capitalized` also applies
//  the *current* locale's casing rules to an English token, which is wrong for some scripts.
//
//  MacHardcodedStringGuardTests could not see it: its pattern is `Api("literal"`, and a ternary
//  puts an expression between the paren and the quote. That wider hole is its own task; this file
//  pins the role labels specifically, because the fix for them is to have exactly one place in the
//  Mac target that turns a role wire value into human text.
//
//  Lives in the iOS test target because it reads the repo tree — see the note in
//  MacHardcodedStringGuardTests about the sandboxed Mac test host.

import XCTest

final class MacRoleLabelGuardTests: XCTestCase {

    /// The words a role renders as in English. Seeing one as a literal in a view means that view
    /// is naming a role itself instead of asking `MacMemberRoleLabel`.
    private static let englishRoleWords = ["Owner", "Admin", "Administrator", "Member", "Viewer"]

    private var macViewsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views")
    }

    private func macViewSources() throws -> [(name: String, source: String)] {
        guard let files = FileManager.default.enumerator(at: macViewsRoot, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate \(macViewsRoot.path)")
            return []
        }
        var sources: [(String, String)] = []
        for case let fileURL as URL in files where fileURL.pathExtension == "swift" {
            sources.append((fileURL.lastPathComponent, try String(contentsOf: fileURL, encoding: .utf8)))
        }
        XCTAssertFalse(sources.isEmpty, "The Mac view tree moved; this guard is scanning nothing.")
        return sources
    }

    /// A role word typed into a view is a translation that will never happen.
    func testNoMacViewSpellsARoleOutInEnglish() throws {
        var violations: [String] = []

        for (name, source) in try macViewSources() {
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                for word in Self.englishRoleWords where code.contains("\"\(word)\"") {
                    violations.append("\(name):\(index + 1) — \"\(word)\"")
                }
            }
        }

        XCTAssertEqual(violations, [], """
            Mac views must render roles with MacMemberRoleLabel.title(for:), not an English literal:
            \(violations.joined(separator: "\n"))
            """)
    }

    /// `.capitalized` on a role is the same bug wearing a different hat: it ships the wire value.
    /// The one sanctioned `role.capitalized` is the `default:` fallback inside `MacMemberRoleLabel`
    /// itself, which is not in this tree.
    func testNoMacViewCapitalizesARoleWireValue() throws {
        var violations: [String] = []

        for (name, source) in try macViewSources() {
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                if code.range(of: "role\\??\\.capitalized", options: [.regularExpression, .caseInsensitive]) != nil {
                    violations.append("\(name):\(index + 1) — \(code)")
                }
            }
        }

        XCTAssertEqual(violations, [], """
            A role's wire value must not be capitalized for display — route it through
            MacMemberRoleLabel.title(for:), which is localized:
            \(violations.joined(separator: "\n"))
            """)
    }
}
