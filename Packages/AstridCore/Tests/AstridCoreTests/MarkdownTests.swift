import AstridCore
import XCTest

final class MarkdownTests: XCTestCase {
    func testBoldIsARunNotAsterisks() {
        XCTAssertEqual(
            CoreRules.markdown("**hi**"),
            [.paragraph([.text(MarkdownRun(text: "hi", bold: true))])])
    }

    func testAReferenceIsAPillWithItsId() {
        XCTAssertEqual(
            CoreRules.markdown("ask @[Jon](u1)"),
            [.paragraph([.text(MarkdownRun(text: "ask ")), .reference(.user, label: "Jon", id: "u1")])])
    }

    func testATaskReferenceIsNotAnImage() {
        guard case .paragraph(let inlines)? = CoreRules.markdown("![Ship it](t9)").first else {
            return XCTFail("a paragraph")
        }
        XCTAssertEqual(inlines, [.reference(.task, label: "Ship it", id: "t9")])
    }

    func testBlockStructureArrives() {
        let blocks = CoreRules.markdown("## Plan\n\n1. one\n2. two\n\n```\nlet x = 1\n```")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .heading(level: 2, [.text(MarkdownRun(text: "Plan"))]))
        guard case .list(ordered: true, start: 1, let items) = blocks[1] else { return XCTFail("a list") }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(blocks[2], .code(language: nil, text: "let x = 1\n"))
    }

    func testANewlineIsALineBreak() {
        XCTAssertEqual(
            CoreRules.markdown("a\nb"),
            [.paragraph([.text(MarkdownRun(text: "a")), .lineBreak, .text(MarkdownRun(text: "b"))])])
    }

    func testAJavascriptLinkIsJustText() {
        guard case .paragraph(let inlines)? = CoreRules.markdown("[x](javascript:alert(1))").first,
              case .text(let run)? = inlines.first else { return XCTFail("a run") }
        XCTAssertNil(run.link)
    }
}
