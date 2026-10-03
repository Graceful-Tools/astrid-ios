//  MarkdownTextTests.swift
//  Regression guard for Task AITD-416 — "Render block markdown in chat bubbles and task
//  comments".
//
//  The phone is where agent prose is read, and it was the one surface still rendering that prose
//  with `.inlineOnlyPreservingWhitespace`: `##` headings, `-` bullets and fenced code blocks
//  arrived as literal characters in /fixall run summaries and completion reports. The Mac had
//  already solved it twice over — `MacMarkdownText` composes the shared `MarkdownBlocks` parser
//  with the shared `attributedWithReferences` pass (AITD-389, AITD-390) — so what iOS needed was
//  the same composition, not a second parser.
//
//  These mirror `MacCommentReferenceLinkTests` deliberately. The two platforms drawing the same
//  comment differently is the drift both tasks exist to end, so the assertions are the same
//  assertions; where they differ is only the view type and the font vocabulary.

import AstridCore
import XCTest
import SwiftUI
@testable import Astrid_App

final class MarkdownTextTests: XCTestCase {

    /// Every link carried by the runs of an attributed string, in order.
    private func links(_ attributed: AttributedString) -> [URL] {
        attributed.runs.compactMap { $0.link }
    }

    /// The visible characters, with the reference markup gone if it was rendered.
    private func plain(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    // MARK: - The bug

    /// The whole report in one assertion: a run summary's heading is a heading, not `##`.
    func testAHeadingIsABlockRatherThanLiteralHashes() {
        XCTAssertEqual(CoreRules.markdown("## Run summary\n\nTwo tasks merged."),
                       [.heading(level: 2, [.text(MarkdownRun(text: "Run summary"))]),
                        .paragraph([.text(MarkdownRun(text: "Two tasks merged."))])],
                       "the bubble draws blocks — `##` must not survive as characters")
    }

    /// …and the same for the other two shapes the report names.
    func testBulletsAndFencesAreBlocksToo() {
        guard case .list(ordered: false, _, let items)? = CoreRules.markdown("- merged\n- pushed").first else {
            return XCTFail("a bulleted list")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(CoreRules.markdown("```\nnpm run predeploy\n```"),
                       [.code(language: nil, text: "npm run predeploy\n")],
                       "a fenced block is its own block — the backticks are markup, not text")
    }

    // MARK: - Fenced code blocks

    /// The language tag is part of the fence, not part of the code. Showing `swift` as the first
    /// line of the snippet would be showing markup.
    func testAFenceDropsItsLanguageTag() {
        XCTAssertEqual(CoreRules.markdown("```swift\nlet x = 1\n```"),
                       [.code(language: "swift", text: "let x = 1\n")])
    }

    /// Inside a fence, markdown stops meaning anything — that is what a fence is for. A `#`
    /// comment in a shell snippet must stay a `#` comment and not become a heading.
    func testAFenceKeepsItsContentsVerbatim() {
        XCTAssertEqual(CoreRules.markdown("```\n# not a heading\n- not a bullet\n```"),
                       [.code(language: nil, text: "# not a heading\n- not a bullet\n")],
                       "block syntax inside a fence is code")
    }

    /// Indentation is meaning in code, so a fence is the one block that must not be trimmed
    /// line by line the way a paragraph is.
    func testAFencePreservesIndentation() {
        XCTAssertEqual(CoreRules.markdown("```\nif x {\n    return y\n}\n```"),
                       [.code(language: nil, text: "if x {\n    return y\n}\n")])
    }

    /// An unterminated fence still has to render as code rather than swallowing the rest of the
    /// message — a truncated agent comment is exactly when this happens. It ends in the one newline
    /// every code block carries, closed or not (astrid-core's fixture-locked markdown, D38).
    func testAnUnclosedFenceStillClosesAtTheEnd() {
        XCTAssertEqual(CoreRules.markdown("```\nnpm run predeploy"),
                       [.code(language: nil, text: "npm run predeploy\n")])
    }

    // MARK: - References still linkify

    /// A `!task` reference in a comment is a tappable link, exactly as it already was before the
    /// bubble learned blocks. This is the property the routing must not cost.
    func testATaskReferenceBecomesATappableLink() {
        let attributed = MarkdownText.attributed("Fixed in ![Sync bug](abc123) yesterday.",
                                                 defaultColor: .primary)

        XCTAssertEqual(links(attributed), [URL(string: "astrid://tasks/abc123")!])
        XCTAssertEqual(plain(attributed), "Fixed in !Sync bug yesterday.",
                       "the reader sees the NAME — `![Sync bug](abc123)` is markup")
    }

    /// All three triggers, since a run summary mixes them.
    func testMentionsAndListsLinkifyTheSameWay() {
        let attributed = MarkdownText.attributed("@[Jon](u1) moved it to #[iOS](l2)",
                                                 defaultColor: .primary)

        XCTAssertEqual(links(attributed),
                       [URL(string: "astrid://users/u1")!, URL(string: "astrid://lists/l2")!])
    }

    /// A bullet keeps its inline marks AND its link — blocks and references compose.
    func testABulletKeepsItsBoldAndStillLinkifies() {
        let attributed = MarkdownText.attributed("**Done** — see ![Sync bug](abc123)",
                                                 defaultColor: .primary)
        XCTAssertEqual(links(attributed), [URL(string: "astrid://tasks/abc123")!])
        XCTAssertEqual(plain(attributed), "Done — see !Sync bug")
    }

    /// The common case — an ordinary message with no markup at all — must come out unchanged.
    func testAPlainMessageIsUnchanged() {
        let attributed = MarkdownText.attributed("**Done** — merged into `main`.",
                                                 defaultColor: .primary)
        XCTAssertTrue(links(attributed).isEmpty)
        XCTAssertEqual(plain(attributed), "Done — merged into main.")
    }

    // MARK: - A block's font is the block's to set

    /// AITD-390's finding, now load-bearing on iOS as well: the reference run must carry NO font,
    /// or a reference inside a `##` heading draws at body size while the words either side of it
    /// stay heading-sized.
    func testAReferenceCarriesNoFontOfItsOwn() {
        let attributed = MarkdownText.attributed("Blocked by ![Sync bug](abc123)",
                                                 defaultColor: .primary)
        for run in attributed.runs where run.link != nil {
            XCTAssertNil(run.font,
                         "the heading/bullet/paragraph sets the font — the reference must not")
        }
    }

    /// …and the shared extension's default is untouched for the callers that still rely on it
    /// (the inline editor preview). Only the block renderers opt out.
    func testTheSharedDefaultStillCarriesBody() {
        let attributed = "see ![Sync bug](abc123)".attributedWithReferences(defaultColor: .primary)
        let referenceRuns = attributed.runs.filter { $0.link != nil }
        XCTAssertEqual(referenceRuns.count, 1)
        XCTAssertEqual(referenceRuns.first?.font, .body)
    }

    /// Headings stop shrinking once they reach the body they introduce — a `####` that renders
    /// smaller than its own paragraph reads as a mistake.
    func testHeadingsStopShrinking() {
        XCTAssertEqual(MarkdownText.headingFont(4), MarkdownText.headingFont(6),
                       "below level 3 the difference is invisible, so it stops")
        XCTAssertEqual(MarkdownText.headingFont(0), MarkdownText.headingFont(1),
                       "a nonsense level clamps rather than crashing or inverting")
    }

    // MARK: - One renderer, both surfaces

    /// Reuse is most of the point: the chat bubble and the comment bubble draw through the SAME
    /// view, and neither keeps the bare inline-only path that caused this.
    func testBothIOSBubblesDrawThroughTheOneComposedRenderer() throws {
        let chat = try RepositoryLocator.source(at: "Astrid App/Views/Chat/ChatMessageBubble.swift")
        XCTAssertTrue(chat.contains("MarkdownText(source: message.content"),
                      "chat renders through the composed renderer")
        XCTAssertFalse(chat.contains("Text(message.content.attributedWithReferences"),
                       "the inline-only path is the bug this replaces")

        let comments = try RepositoryLocator.source(
            at: "Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift")
        XCTAssertTrue(comments.contains("MarkdownText(source: comment.content"),
                      "a completion report is read in this view — it needs blocks most of all")
        XCTAssertFalse(comments.contains("Text(comment.content.attributedWithReferences"),
                       "the inline-only path is the bug this replaces")
    }

    /// The renderer must draw through the SHARED view, which asks astrid-core what the text
    /// means, rather than growing an iOS-local parser — a second copy is how a deep-link scheme
    /// changes on one platform only.
    func testTheRendererUsesTheSharedPasses() throws {
        let renderer = try RepositoryLocator.source(at: "Astrid App/Views/Components/MarkdownText.swift")
        XCTAssertTrue(renderer.contains("MarkdownView(source:"),
                      "the phone draws through the shared view, not an iOS-local one")
        XCTAssertFalse(renderer.contains("NSRegularExpression"),
                       "a second copy of the reference pattern is exactly the drift to avoid")

        let shared = try RepositoryLocator.source(at: "Astrid App/Core/Platform/MarkdownView.swift")
        XCTAssertTrue(shared.contains("CoreRules.markdown"),
                      "what the text means is astrid-core's answer, the web's own rendering")
        XCTAssertFalse(shared.contains("NSRegularExpression"),
                       "no pattern of its own: references arrive from the core as pills")
    }
}
