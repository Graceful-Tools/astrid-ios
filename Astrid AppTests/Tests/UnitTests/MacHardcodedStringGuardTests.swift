//  MacHardcodedStringGuardTests.swift
//  Regression guard for Task d0e9d692 — "[mac] localize the remaining dialog + toolbar strings".
//
//  A few user-facing strings survived the Mac localization pass because they sat inside
//  confirmationDialog / contextMenu / alert / help builders, which an earlier grep for `Text("…")`
//  never covered: "Delete this list?", "Remove Favorite"/"Favorite", "Mark Incomplete"/"Complete",
//  "<name> is thinking…", "<n> occurrences", "Assigned to <name>", the OpenClaw alert title.
//
//  Widened for AITD-325. The first version matched `Api("` — a user-facing builder whose FIRST
//  CHARACTER after the paren is a quote — so anything with an expression in between was invisible:
//  `Text(isOwner(m) ? "Owner" : …)`, `Button(existing == nil ? "Create" : "Save")`. It read as if
//  it covered `Text("…")` everywhere; it covered only the unconditional case, and ~14 English
//  strings were hiding behind ternaries and `??` fallbacks. It also missed `LabeledContent`
//  entirely, and being line-based it never saw the second and third branch of a ternary that
//  wrapped across lines.
//
//  This lives in the iOS test target on purpose: it reads the repo tree, and the sandboxed Mac
//  test host is the wrong place to do that (see MacLocalizationTests, which asserts the built
//  bundle instead).

import XCTest

final class MacHardcodedStringGuardTests: XCTestCase {

    /// SwiftUI APIs whose first string argument is shown to a human.
    private let userFacingAPIs = ["Text", "Button", "Label", "Toggle", "Picker", "Menu", "Section",
                                  "Link", "Stepper", "TextField", "LabeledContent",
                                  "confirmationDialog", "alert",
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

        var violations: [String] = []
        for case let fileURL as URL in files where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            for (index, _) in lines.enumerated() {
                for literal in try proseLiterals(atLine: index, of: lines) {
                    violations.append("\(fileURL.lastPathComponent):\(index + 1) — \"\(literal)\"")
                }
            }
        }

        XCTAssertEqual(violations, [], """
            Mac UI strings must come from Localizable.strings, not from a literal.
            A string that is deliberately not prose — a file extension, a URL placeholder — goes
            through Text(verbatim:), which this guard skips on purpose.
            \(violations.joined(separator: "\n"))
            """)
    }

    // MARK: - Finding the prose

    /// The prose literals a human would read off the screen from the builders opening on this line.
    ///
    /// Only the builder's FIRST argument is examined, and only after every nested call expression
    /// inside it has been removed. Those two rules are what keep the guard honest: without them a
    /// widened match drowns in SF Symbol names (`systemImage: "gearshape"`), `.tag("indented")`
    /// values, `openWindow(id: "main")` in a Button's action closure, and — worst — the localization
    /// call itself, so that every `Text(NSLocalizedString("lists.owner", …))` reports its own key
    /// as untranslated prose.
    private func proseLiterals(atLine index: Int, of lines: [String]) throws -> [String] {
        let code = lines[index].trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { return [] }

        var found: [String] = []
        for open in openingParens(ofUserFacingBuildersIn: code) {
            // A ternary can wrap, so the argument is read across continuation lines. `"Search"` was
            // reported at MacRootView:1402 while `"My Tasks"` and `"Tasks"` sat one and two lines
            // below it, inside the same navigationTitle(.
            let argument = firstArgument(from: code, openParenAt: open, continuedBy: lines, after: index)

            // Text(verbatim:) is the explicit "this is not prose" opt-out.
            guard !argument.trimmingCharacters(in: .whitespaces).hasPrefix("verbatim:") else { continue }

            let bare = strippingComparisons(from: strippingNestedCalls(from: argument))
            for literal in literals(in: bare) where !allowed.contains(literal) && isProse(literal) {
                found.append(literal)
            }
        }
        return found
    }

    /// Index just past the `(` of every user-facing builder opening on this line.
    private func openingParens(ofUserFacingBuildersIn code: String) -> [String.Index] {
        var opens: [String.Index] = []
        for api in userFacingAPIs {
            var searchFrom = code.startIndex
            while let range = code.range(of: api + "(", range: searchFrom..<code.endIndex) {
                searchFrom = range.upperBound
                // `.help(` and `Text(` only — not `myHelp(` or `AttributedText(`.
                let precededByIdentifier = range.lowerBound > code.startIndex && {
                    let before = code[code.index(before: range.lowerBound)]
                    return before.isLetter || before.isNumber || before == "_"
                }()
                guard !precededByIdentifier else { continue }
                opens.append(range.upperBound)
            }
        }
        return opens
    }

    /// The builder's first argument: everything up to the top-level `,` or the closing `)`.
    ///
    /// Taking only the first argument is what excludes `systemImage:`, `value:` and the rest — the
    /// guard's premise, unchanged since the first version, is that the FIRST string argument is the
    /// one a human reads.
    private func firstArgument(from code: String, openParenAt open: String.Index,
                               continuedBy lines: [String], after index: Int) -> String {
        var text = String(code[open...])
        var lookahead = index
        // Up to a handful of continuation lines — enough for a wrapped ternary, not the whole file.
        while scan(text) == nil, lookahead + 1 < lines.count, lookahead - index < 4 {
            lookahead += 1
            text += " " + lines[lookahead].trimmingCharacters(in: .whitespaces)
        }
        return scan(text) ?? text
    }

    /// The first argument within `text`, or nil while the parens are still unbalanced.
    private func scan(_ text: String) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var argument = ""
        for character in text {
            if escaped { escaped = false; argument.append(character); continue }
            if inString {
                if character == "\\" { escaped = true }
                if character == "\"" { inString = false }
                argument.append(character)
                continue
            }
            switch character {
            case "\"": inString = true
            case "(", "[", "{": depth += 1
            case ")", "]", "}":
                if depth == 0 { return argument }
                depth -= 1
            case "," where depth == 0:
                return argument
            default: break
            }
            argument.append(character)
        }
        return nil
    }

    /// Calls whose ARGUMENTS still reach the screen, so only the callee's name is dropped.
    ///
    /// `String(format: NSLocalizedString("mac.replying_to", …), author ?? "message", body)` — the
    /// format string is localized, but the substitutions are shown verbatim, and "message" is
    /// exactly the kind of English fallback this guard exists to catch.
    private let transparentWrappers: Set<String> = ["String"]

    /// Removes `name(…)` call expressions, arguments and all.
    ///
    /// One rule for every wrapper: `NSLocalizedString("key", comment:)`, `Brand.localized("key")`,
    /// `MacMemberRoleLabel.title(for: isOwner(m) ? "owner" : m.role)`. A literal handed to another
    /// function is that function's input — a key, a role, a symbol name — not prose on screen.
    private func strippingNestedCalls(from argument: String) -> String {
        var result = ""
        var pending = ""            // the identifier being read, so `foo` in `foo(`
        var iterator = argument.startIndex
        var inString = false
        var escaped = false

        while iterator < argument.endIndex {
            let character = argument[iterator]
            if escaped { escaped = false; pending.append(character); iterator = argument.index(after: iterator); continue }
            if inString {
                if character == "\\" { escaped = true }
                if character == "\"" { inString = false }
                pending.append(character)
                iterator = argument.index(after: iterator)
                continue
            }
            if character == "\"" {
                inString = true
                pending.append(character)
                iterator = argument.index(after: iterator)
                continue
            }
            if character == "(", isIdentifierTail(pending) {
                let nameLength = identifierTailLength(pending)
                let name = String(pending.suffix(nameLength))
                pending = String(pending.dropLast(nameLength))
                result += pending
                pending = ""
                if transparentWrappers.contains(name) {
                    // Keep walking into the argument list; a nested NSLocalizedString inside it is
                    // still stripped by this same loop on the next turn.
                    iterator = argument.index(after: iterator)
                } else {
                    // Drop the callee name along with its whole argument list.
                    iterator = skipBalanced(argument, from: iterator)
                }
                continue
            }
            pending.append(character)
            iterator = argument.index(after: iterator)
        }
        return result + pending
    }

    /// Removes `== "…"` / `!= "…"` operands — a status comparison inside a ternary CONDITION is not
    /// the string being displayed (`Text(agent.status == "active" ? … : …)`).
    private func strippingComparisons(from argument: String) -> String {
        argument.replacingOccurrences(of: "[=!]=\\s*\"(\\\\.|[^\"\\\\])*\"",
                                      with: " ",
                                      options: .regularExpression)
    }

    /// Every string literal left in the expression.
    private func literals(in text: String) -> [String] {
        var found: [String] = []
        var current: String?
        var escaped = false
        for character in text {
            if var literal = current {
                if escaped { escaped = false; literal.append(character); current = literal; continue }
                if character == "\\" { escaped = true; literal.append(character); current = literal; continue }
                if character == "\"" { found.append(literal); current = nil; continue }
                literal.append(character)
                current = literal
            } else if character == "\"" {
                current = ""
            }
        }
        return found
    }

    // MARK: - Small helpers

    private func isIdentifierTail(_ text: String) -> Bool { identifierTailLength(text) > 0 }

    /// How many trailing characters of `text` form an identifier — the callee's name.
    private func identifierTailLength(_ text: String) -> Int {
        var length = 0
        for character in text.reversed() {
            guard character.isLetter || character.isNumber || character == "_" else { break }
            length += 1
        }
        return length
    }

    /// The index just past the `)` closing the `(` at `start`.
    private func skipBalanced(_ text: String, from start: String.Index) -> String.Index {
        var depth = 0
        var index = start
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if escaped { escaped = false; continue }
            if inString {
                if character == "\\" { escaped = true }
                if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return index
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
