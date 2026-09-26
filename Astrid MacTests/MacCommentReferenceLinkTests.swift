//  MacCommentReferenceLinkTests.swift
//  Regression guard for Task AITD-390 — "[mac] linkify Astrid task references in comments, like
//  chat messages already do".
//
//  AITD-389 gave Mac comments a markdown renderer and deliberately left references alone, which
//  left three surfaces with three different answers: Mac chat linkified but did not render
//  markdown, Mac comments rendered markdown but did not linkify, and web's
//  `renderMarkdownWithLinks` did both for both. So `!Fix the sync bug` in a comment arrived as
//  the characters `![Fix the sync bug](abc123)` — a markdown image, if anything parsed it at all.
//
//  The collision the report feared is not there. `attributedWithReferences` splits the text at
//  each reference and markdown-parses the gaps, so inline marks and references have always
//  composed. What did not compose was BLOCK structure: `MacMarkdownText` parsed blocks with the
//  shared `MarkdownBlocks` and then called `AttributedString(markdown:)` on each block directly,
//  stepping around the reference pass entirely.
//
//  What these pin, then: ONE composed renderer on the Mac — blocks from the shared parser, inline
//  marks and references from the shared extension — serving BOTH the comment and the chat bubble,
//  and doing it without a block's own font being overwritten from underneath it.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacCommentReferenceLinkTests: XCTestCase {

    private func macSource(_ path: String) throws -> String {
        let url = RepositoryLocator.root
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every link carried by the runs of an attributed string, in order.
    private func links(_ attributed: AttributedString) -> [URL] {
        attributed.runs.compactMap { $0.link }
    }

    /// The visible characters, with the reference markup gone if it was rendered.
    private func plain(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    // MARK: - The bug

    /// The whole report in one assertion: a task reference in a comment is a link, not markup.
    func testATaskReferenceInACommentBecomesATappableLink() {
        let attributed = MacMarkdownText.attributed("Fixed in ![Sync bug](abc123) yesterday.")

        XCTAssertEqual(links(attributed), [URL(string: "astrid://tasks/abc123")!],
                       "a ! reference must carry the astrid://tasks deep link the Mac already parses")
        XCTAssertEqual(plain(attributed), "Fixed in !Sync bug yesterday.",
                       "the reader sees the NAME — `![Sync bug](abc123)` is markup, not text")
    }

    /// All three trigger characters, since a comment mixes them. The schemes are the shared
    /// extension's; this pins that the Mac's block renderer reaches them at all.
    func testMentionsAndListsLinkifyTheSameWay() {
        let attributed = MacMarkdownText.attributed("@[Jon](u1) moved it to #[iOS](l2)")

        XCTAssertEqual(links(attributed),
                       [URL(string: "astrid://users/u1")!, URL(string: "astrid://lists/l2")!],
                       "@ links to a profile and # to a list, exactly as chat has always done")
    }

    // MARK: - Blocks and references compose

    /// The half AITD-389 built has to survive: block structure still comes from the SHARED parser,
    /// and a reference inside a bullet linkifies without eating the bullet's inline marks.
    func testABulletKeepsItsBoldAndStillLinkifies() {
        let blocks = MarkdownBlocks.parse("- **Done** — see ![Sync bug](abc123)")
        XCTAssertEqual(blocks, [.bulletItem(text: "**Done** — see ![Sync bug](abc123)")],
                       "the block parser hands the reference through untouched, for the inline pass")

        let attributed = MacMarkdownText.attributed("**Done** — see ![Sync bug](abc123)")
        XCTAssertEqual(links(attributed), [URL(string: "astrid://tasks/abc123")!])
        XCTAssertEqual(plain(attributed), "Done — see !Sync bug",
                       "`**Done**` renders as bold text, so the asterisks are gone from the characters")
    }

    /// A comment with no reference at all must come out exactly as AITD-389 left it — this is the
    /// common case, and a renderer that only works on referenced text is a regression for it.
    func testAPlainMarkdownCommentIsUnchanged() {
        let attributed = MacMarkdownText.attributed("**Done** — merged into `main`.")
        XCTAssertTrue(links(attributed).isEmpty)
        XCTAssertEqual(plain(attributed), "Done — merged into main.")
    }

    // MARK: - A block's font is the block's to set

    /// The one thing that had to give in the shared extension. It hardcoded `.body` on every
    /// reference run, which is right for a chat bubble and wrong inside a `##` heading: the
    /// reference would render at body size while the words either side of it were heading-sized.
    /// The block renderer asks for no font so the block's own `.font(...)` reaches the run.
    func testAReferenceInsideAHeadingDoesNotOverrideTheHeadingFont() {
        let attributed = MacMarkdownText.attributed("Blocked by ![Sync bug](abc123)")
        for run in attributed.runs where run.link != nil {
            XCTAssertNil(run.font,
                         "a reference must not carry its own font — the heading/bullet/paragraph sets it")
        }
    }

    /// …and iOS does not move. Chat and the iOS comment list call the shared extension with no
    /// font argument and must keep the `.body` they have always had.
    func testTheSharedDefaultStillCarriesBodyForTheCallersThatRelyOnIt() {
        let attributed = "see ![Sync bug](abc123)".attributedWithReferences(defaultColor: .primary)
        let referenceRuns = attributed.runs.filter { $0.link != nil }
        XCTAssertEqual(referenceRuns.count, 1)
        XCTAssertEqual(referenceRuns.first?.font, .body,
                       "the default is unchanged — only the Mac block renderer opts out")
    }

    // MARK: - One renderer, both surfaces

    /// Reuse is most of the point. The comment bubble and the chat bubble draw through the SAME
    /// composed view — three surfaces with three answers is what AITD-390 exists to end.
    func testBothMacBubblesDrawThroughTheOneComposedRenderer() throws {
        let detail = try macSource("Astrid Mac/Views/MacCommentThread.swift")   // the shared thread (AITD-432)
        XCTAssertTrue(detail.contains("MacMarkdownText(source: c.content"),
                      "the comment bubble renders through the composed renderer")

        let chat = try macSource("Astrid Mac/Views/MacChatPanelView.swift")
        XCTAssertTrue(chat.contains("MacMarkdownText(source: m.content"),
                      "chat renders through it too — otherwise markdown in a message stays raw syntax")
        XCTAssertFalse(chat.contains("Text(m.content.attributedWithReferences"),
                       "the bare inline-only path is the drift this replaces")
    }

    /// The composed renderer must go through the SHARED extension rather than growing a Mac-local
    /// copy of the reference regex — a second copy is how a scheme changes on one platform only.
    func testTheRendererUsesTheSharedReferencePass() throws {
        let renderer = try macSource("Astrid Mac/Views/MacMarkdownText.swift")
        XCTAssertTrue(renderer.contains("attributedWithReferences"),
                      "references come from the shared String extension, not a Mac-local regex")
        XCTAssertTrue(renderer.contains("MarkdownBlocks.parse"),
                      "blocks still come from the shared parser")
        XCTAssertFalse(renderer.contains("NSRegularExpression"),
                       "a second copy of the reference pattern is exactly the drift to avoid")
    }
}
#endif
