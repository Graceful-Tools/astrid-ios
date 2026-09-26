//  MacCommentMarkdownTests.swift
//  Regression guard for Task AITD-389 — "[mac] render task comments as markdown. reuse what we
//  do for task details which already renders markdown".
//
//  The Mac drew `Text(c.content)`, so a comment written in markdown arrived as its own syntax:
//  `**Done**` with the asterisks, `- one` as a line beginning with a hyphen, `## Gates` with the
//  hashes. Every other surface renders it — the web bubble these comments are read in most often
//  (`components/shared/MessageBubble.tsx`) runs the content through `renderMarkdownWithLinks`
//  unconditionally, for every comment type — and the Mac's own task description already had a
//  renderer sitting next to it.
//
//  So the fix is reuse, and that is most of what these guard: ONE markdown renderer on the Mac,
//  over the SHARED block parser, used by both the description and the comment. The other half is
//  the bubble's width — a renderer built for a column that owns its width will stretch a comment
//  bubble across the whole thread if nobody says otherwise.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacCommentMarkdownTests: XCTestCase {

    private func macSource(_ path: String) throws -> String {
        let url = RepositoryLocator.root
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The body of `commentBubble(_:)` — the function that draws one comment.
    private func commentBubbleBody() throws -> String {
        let source = try macSource("Astrid Mac/Views/MacCommentThread.swift")   // moved from MacTaskDetailView (AITD-432)
        guard let start = source.range(of: "private func commentBubble(") else {
            XCTFail("commentBubble() not found — did it move?")
            return ""
        }
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    /// ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - The bug

    /// The whole report in one assertion: a comment's text is markdown, and has to be rendered.
    func testCommentBubbleRendersItsTextAsMarkdown() throws {
        let body = try commentBubbleBody()
        XCTAssertTrue(body.contains("MacMarkdownText"),
                      "A comment is markdown — drawing it with a bare Text shows the syntax instead of the formatting")
        // `MacCommentBubble.showsText(c.content)` is the emptiness gate and has to stay; it just
        // happens to contain the same characters, so take it out before looking for the drawing.
        let drawing = body.replacingOccurrences(of: "showsText(c.content)", with: "")
        XCTAssertFalse(drawing.contains("Text(c.content)"),
                       "Raw Text(c.content) is exactly the bug: `**bold**` and `- item` arrive as characters")
    }

    /// Reuse, not a second renderer: the same view the description uses. Two Mac markdown views
    /// is how a heading ends up one size in a description and another in a comment.
    func testItIsTheSameRendererTheDescriptionUses() throws {
        XCTAssertTrue(try macSource("Astrid Mac/Views/MacTaskFieldsView.swift").contains("MacMarkdownText"),
                      "the description renders through MacMarkdownText — the comment must use that one")
        let renderers = ["Astrid Mac/Views/MacMarkdownText.swift"]
        for path in renderers {
            XCTAssertTrue(try macSource(path).contains("MarkdownBlocks.parse"),
                          "\(path) must parse with the SHARED block parser, not a Mac-local copy")
        }
    }

    // MARK: - A bubble is not a column

    /// A description owns its column, so it fills the width it is given. A comment sits in a
    /// bubble sized to its content — filling there stretches every bubble across the thread and
    /// undoes the right-aligned "mine" layout. `nil` is "no constraint": as wide as its text.
    func testABubbleHugsItsTextWhileADescriptionFillsItsColumn() {
        XCTAssertEqual(MacMarkdownText.maxWidth(fillsWidth: true), .infinity)
        XCTAssertNil(MacMarkdownText.maxWidth(fillsWidth: false),
                     "a comment bubble must be as wide as its text, not as wide as the thread")
    }

    /// …and the bubble actually asks for that. A parameter nobody passes changes nothing.
    func testTheBubbleAsksToHug() throws {
        XCTAssertTrue(try commentBubbleBody().contains("fillsWidth: false"),
                      "commentBubble must render markdown in hug-your-text mode")
    }

    // MARK: - What a comment on this board actually looks like

    /// The comments this renders are strategy notes and completion reports: bold leads, bullet
    /// lists, `##` headings. All of it has to come out as structure rather than as one long line
    /// of punctuation — the shared parser does the work, this pins that a comment's shape reaches it.
    func testARealCommentParsesIntoBlocksNotOneParagraph() {
        let comment = """
        **Done — merged into `main`.**

        - the rule moved into one place
        - the drawer is shared

        ## Gates
        predeploy green.
        """
        let blocks = MarkdownBlocks.parse(comment)
        XCTAssertEqual(blocks.count, 5, "lead, two bullets, heading, closing paragraph")
        XCTAssertEqual(blocks.first, .paragraph(text: "**Done — merged into `main`.**"),
                       "inline marks stay in the text for AttributedString to draw")
        XCTAssertEqual(blocks[1], .bulletItem(text: "the rule moved into one place"))
        XCTAssertEqual(blocks[3], .heading(level: 2, text: "Gates"))
    }
}
#endif
