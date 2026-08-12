//  MarkdownBlocksTests.swift
//  Task f5520874 — "[Mac] Render text on Description as formatted markdown. When editing
//  show the plain text."
//
//  `AttributedString(markdown:)` handles INLINE marks (bold, italic, links) but SwiftUI's
//  Text does not render block structure from it — a heading and an ordered list come out as
//  plain lines with their syntax stripped or intact. So the blocks are parsed here, and the
//  view renders each one; inline marks inside a block still go through AttributedString.
//
//  Shared rather than Mac-only: a description is a description on every platform.

import XCTest
@testable import Astrid_App

final class MarkdownBlocksTests: XCTestCase {

    // MARK: headings

    func testHeadingLevelsAreRecognised() {
        XCTAssertEqual(MarkdownBlocks.parse("# Title"), [.heading(level: 1, text: "Title")])
        XCTAssertEqual(MarkdownBlocks.parse("## Sub"), [.heading(level: 2, text: "Sub")])
        XCTAssertEqual(MarkdownBlocks.parse("### Small"), [.heading(level: 3, text: "Small")])
    }

    /// `#header` with no space is not a heading in markdown — and people write `#1` meaning
    /// a number, which must not silently become a title.
    func testAHashWithoutASpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownBlocks.parse("#header"), [.paragraph(text: "#header")])
    }

    /// Deeper than 3 still renders as a heading rather than falling back to body text; it
    /// just stops getting smaller.
    func testDeepHeadingsAreClampedNotDropped() {
        XCTAssertEqual(MarkdownBlocks.parse("###### Deep"), [.heading(level: 6, text: "Deep")])
    }

    // MARK: lists

    func testOrderedItemsKeepTheirOwnNumbers() {
        XCTAssertEqual(MarkdownBlocks.parse("1. list\n2. List"),
                       [.orderedItem(number: 1, text: "list"), .orderedItem(number: 2, text: "List")])
    }

    /// A list that starts at 3 renders as 3 — renumbering someone's list is a lie about
    /// what they wrote.
    func testAListThatStartsPartwayKeepsItsNumbering() {
        XCTAssertEqual(MarkdownBlocks.parse("3. third"), [.orderedItem(number: 3, text: "third")])
    }

    func testBulletsAreRecognisedInBothSpellings() {
        XCTAssertEqual(MarkdownBlocks.parse("- one\n* two"),
                       [.bulletItem(text: "one"), .bulletItem(text: "two")])
    }

    /// "3.5 hours" is not a list item.
    func testANumberWithoutADotAndSpaceIsProse() {
        XCTAssertEqual(MarkdownBlocks.parse("3.5 hours"), [.paragraph(text: "3.5 hours")])
    }

    // MARK: paragraphs

    /// Consecutive plain lines are ONE paragraph, as markdown means them — otherwise a
    /// wrapped sentence renders with a gap at every line break.
    func testConsecutiveLinesJoinIntoOneParagraph() {
        XCTAssertEqual(MarkdownBlocks.parse("one\ntwo"), [.paragraph(text: "one two")])
    }

    /// A blank line ends the paragraph.
    func testABlankLineSeparatesParagraphs() {
        XCTAssertEqual(MarkdownBlocks.parse("one\n\ntwo"),
                       [.paragraph(text: "one"), .paragraph(text: "two")])
    }

    /// A list interrupts a paragraph without needing a blank line before it.
    func testAListEndsTheParagraphAboveIt() {
        XCTAssertEqual(MarkdownBlocks.parse("intro\n- one"),
                       [.paragraph(text: "intro"), .bulletItem(text: "one")])
    }

    func testEmptyInputHasNoBlocks() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("   \n\n  "), [])
    }

    // MARK: the whole thing, as it was actually typed into the task

    func testTheDescriptionFromTheTask() {
        let source = "**bold title**\n\n1. list\n2. List\n\n# header"
        XCTAssertEqual(MarkdownBlocks.parse(source), [
            .paragraph(text: "**bold title**"),   // inline marks survive for AttributedString
            .orderedItem(number: 1, text: "list"),
            .orderedItem(number: 2, text: "List"),
            .heading(level: 1, text: "header"),
        ])
    }

    /// Inline syntax is left INSIDE the block text — the view hands it to AttributedString,
    /// which is what actually knows how to draw bold.
    func testInlineMarksAreLeftForTheInlineParser() {
        XCTAssertEqual(MarkdownBlocks.parse("- has **bold** in it"),
                       [.bulletItem(text: "has **bold** in it")])
    }
}
