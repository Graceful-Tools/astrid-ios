//  MacHardcodedStringGuardTests.swift
//  Regression guard for Task d0e9d692 — "[mac] localize the remaining dialog + toolbar strings".
//
//  A few user-facing strings survived the Mac localization pass because they sat inside
//  confirmationDialog / contextMenu / alert / help builders, which an earlier grep for `Text("…")`
//  never covered: "Delete this list?", "Remove Favorite"/"Favorite", "Mark Incomplete"/"Complete",
//  "<name> is thinking…", "<n> occurrences", "Assigned to <name>", the OpenClaw alert title.
//
//  This lives in the iOS test target on purpose: it reads the repo tree, and the sandboxed Mac
//  test host is the wrong place to do that (see MacLocalizationTests, which asserts the built
//  bundle instead).

import XCTest

final class MacHardcodedStringGuardTests: XCTestCase {

    /// SwiftUI APIs whose first string argument is shown to a human.
    private let userFacingAPIs = ["Text", "Button", "Label", "Toggle", "Picker", "Menu", "Section",
                                  "Link", "Stepper", "TextField", "confirmationDialog", "alert",
                                  "navigationTitle", "help", "accessibilityLabel"]

    /// The product name is the same word in every language.
    private let allowed: Set<String> = ["Astrid", "astrid", "Astrid Mac"]

    func testNoUserFacingLiteralsInTheMacTarget() throws {
        let macRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac")

        guard let files = FileManager.default.enumerator(at: macRoot, includingPropertiesForKeys: nil) else {
            return XCTFail("Could not enumerate \(macRoot.path)")
        }

        // `Api("literal"` — the opening argument of a user-facing view builder.
        let pattern = "\\b(\(userFacingAPIs.joined(separator: "|")))\\(\\s*\"([^\"]*)\""
        let regex = try NSRegularExpression(pattern: pattern)

        var violations: [String] = []
        for case let fileURL as URL in files where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                let range = NSRange(code.startIndex..., in: code)
                for match in regex.matches(in: code, range: range) {
                    guard let r = Range(match.range(at: 2), in: code) else { continue }
                    let literal = String(code[r])
                    guard !allowed.contains(literal), isProse(literal) else { continue }
                    violations.append("\(fileURL.lastPathComponent):\(index + 1) — \"\(literal)\"")
                }
            }
        }

        XCTAssertEqual(violations, [], """
            Mac UI strings must come from Localizable.strings, not from a literal:
            \(violations.joined(separator: "\n"))
            """)
    }

    /// Prose = words a translator would have to translate. Interpolations are stripped first, so
    /// `Text("\\(count)")` and `Text("\\(a) · \\(b)")` are fine while `Text("\\(n) occurrences")` is not.
    private func isProse(_ literal: String) -> Bool {
        var stripped = literal
        while let open = stripped.range(of: "\\("),
              let close = stripped.range(of: ")", range: open.upperBound..<stripped.endIndex) {
            stripped.removeSubrange(open.lowerBound..<close.upperBound)
        }
        // Two consecutive letters is a word; "%@", "·", "+" and digits are not.
        return stripped.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil
    }
}
