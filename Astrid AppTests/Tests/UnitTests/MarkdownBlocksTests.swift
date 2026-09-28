//  MarkdownBlocksTests.swift
//  Task f5520874 — "[Mac] Render text on Description as formatted markdown. When editing
//  show the plain text."
//
//  What a text MEANS — its blocks and inline marks — is astrid-core's `markdown::render`, the web's
//  own rendering (docs/CORE_MIGRATION.md). These are the Apple apps' expectations of it, carried
//  over from the Swift parser it replaced, run against the core. One changed on purpose: a newline
//  inside a paragraph is a line break, as on the web (`breaks: true`), where the old parser joined
//  the lines with a space.

import AstridCore
import XCTest
@testable import Astrid_App

final class MarkdownBlocksTests: XCTestCase {

    /// The rendering as one readable line per block (or list item): a kind, then the text.
    private func outline(_ source: String) -> [String] {
        CoreRules.markdown(source).flatMap { block -> [String] in
            switch block {
            case .paragraph(let inlines): return ["p " + text(inlines)]
            case .heading(let level, let inlines): return ["h\(level) " + text(inlines)]
            case .code(_, let code): return ["code " + code]
            case .list(let ordered, let start, let items):
                return items.enumerated().map { index, item in
                    let marker = ordered ? "\(start + index)." : "•"
                    return marker + " " + item.blocks.map(self.text).joined(separator: " ")
                }
            case .quote: return ["quote"]
            case .rule: return ["rule"]
            case .table: return ["table"]
            }
        }
    }

    private func text(_ block: MarkdownBlock) -> String {
        if case .paragraph(let inlines) = block { return text(inlines) }
        return ""
    }

    private func text(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let run): return run.text
            case .reference(_, let label, _): return label
            case .lineBreak: return "\n"
            }
        }.joined()
    }

    // MARK: headings

    func testHeadingLevelsAreRecognised() {
        XCTAssertEqual(outline("# Title"), ["h1 Title"])
        XCTAssertEqual(outline("## Sub"), ["h2 Sub"])
        XCTAssertEqual(outline("### Small"), ["h3 Small"])
    }

    /// `#header` with no space is not a heading in markdown — and people write `#1` meaning
    /// a number, which must not silently become a title.
    func testAHashWithoutASpaceIsNotAHeading() {
        XCTAssertEqual(outline("#header"), ["p #header"])
    }

    /// Deeper than 3 still renders as a heading rather than falling back to body text; it
    /// just stops getting smaller.
    func testDeepHeadingsAreClampedNotDropped() {
        XCTAssertEqual(outline("###### Deep"), ["h6 Deep"])
    }

    // MARK: lists

    func testOrderedItemsKeepTheirOwnNumbers() {
        XCTAssertEqual(outline("1. list\n2. List"), ["1. list", "2. List"])
    }

    /// A list that starts at 3 renders as 3 — renumbering someone's list is a lie about
    /// what they wrote.
    func testAListThatStartsPartwayKeepsItsNumbering() {
        XCTAssertEqual(outline("3. third"), ["3. third"])
    }

    func testBulletsAreRecognisedInBothSpellings() {
        XCTAssertEqual(outline("- one\n- two"), ["• one", "• two"])
        XCTAssertEqual(outline("* one"), ["• one"])
    }

    /// "3.5 hours" is not a list item.
    func testANumberWithoutADotAndSpaceIsProse() {
        XCTAssertEqual(outline("3.5 hours"), ["p 3.5 hours"])
    }

    // MARK: paragraphs

    /// A newline inside a paragraph is a line break, as the web draws it — the old Swift parser
    /// joined the lines with a space, so a message typed on two lines read as one on Apple only.
    func testANewlineIsALineBreakAsOnTheWeb() {
        XCTAssertEqual(outline("one\ntwo"), ["p one\ntwo"])
    }

    /// A blank line ends the paragraph.
    func testABlankLineSeparatesParagraphs() {
        XCTAssertEqual(outline("one\n\ntwo"), ["p one", "p two"])
    }

    /// A list interrupts a paragraph without needing a blank line before it.
    func testAListEndsTheParagraphAboveIt() {
        XCTAssertEqual(outline("intro\n- one"), ["p intro", "• one"])
    }

    func testEmptyInputHasNoBlocks() {
        XCTAssertEqual(outline(""), [])
        XCTAssertEqual(outline("   \n\n  "), [])
    }

    // MARK: the whole thing, as it was actually typed into the task

    func testTheDescriptionFromTheTask() {
        let source = "**bold title**\n\n1. list\n2. List\n\n# header"
        XCTAssertEqual(outline(source), ["p bold title", "1. list", "2. List", "h1 header"])
    }

    /// Inline marks are the core's too: bold arrives as a bold run inside the item, not as
    /// asterisks for a second parser to find.
    func testInlineMarksArriveAsRuns() {
        guard case .list(_, _, let items)? = CoreRules.markdown("- has **bold** in it").first,
              case .paragraph(let inlines)? = items.first?.blocks.first else {
            return XCTFail("a list item with a paragraph")
        }
        XCTAssertEqual(inlines, [
            .text(MarkdownRun(text: "has ")),
            .text(MarkdownRun(text: "bold", bold: true)),
            .text(MarkdownRun(text: " in it")),
        ])
    }
}
