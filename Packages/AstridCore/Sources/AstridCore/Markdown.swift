import Foundation

/// What a description, a comment or a chat message says, as blocks a view draws — astrid-core's
/// `markdown::render`, which mirrors the web's `renderMarkdownWithLinks`: full GitHub-flavoured
/// markdown with `breaks: true`, bare URLs as links, only `http`/`https`/`mailto` links kept, HTML
/// as text, and Astrid's `@[Name](id)` / `#[List](id)` / `![Task](id)` references as pills.
///
/// The core decides what the text *means*; the view decides fonts and colours, and nothing else.
public indirect enum MarkdownBlock: Equatable, Sendable, Decodable {
    case paragraph([MarkdownInline])
    /// 1 through 6.
    case heading(level: Int, [MarkdownInline])
    /// A fenced or indented block, verbatim.
    case code(language: String?, text: String)
    /// `start` is the first number of an ordered list, as the author wrote it; `1` for bullets.
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case quote([MarkdownBlock])
    case rule
    case table(alignments: [MarkdownAlignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]])

    private enum Keys: String, CodingKey {
        case kind, inlines, level, language, text, ordered, start, items, blocks, alignments, header, rows
    }

    public init(from decoder: Decoder) throws {
        let block = try decoder.container(keyedBy: Keys.self)
        switch try block.decode(String.self, forKey: .kind) {
        case "paragraph":
            self = .paragraph(try block.decode([MarkdownInline].self, forKey: .inlines))
        case "heading":
            self = .heading(
                level: try block.decode(Int.self, forKey: .level),
                try block.decode([MarkdownInline].self, forKey: .inlines))
        case "code":
            self = .code(
                language: try block.decodeIfPresent(String.self, forKey: .language),
                text: try block.decode(String.self, forKey: .text))
        case "list":
            self = .list(
                ordered: try block.decode(Bool.self, forKey: .ordered),
                start: try block.decode(Int.self, forKey: .start),
                items: try block.decode([MarkdownListItem].self, forKey: .items))
        case "quote":
            self = .quote(try block.decode([MarkdownBlock].self, forKey: .blocks))
        case "rule":
            self = .rule
        case "table":
            self = .table(
                alignments: try block.decode([MarkdownAlignment].self, forKey: .alignments),
                header: try block.decode([[MarkdownInline]].self, forKey: .header),
                rows: try block.decode([[[MarkdownInline]]].self, forKey: .rows))
        default:
            // A block kind a newer core draws and this build does not: keep its words.
            self = .paragraph([])
        }
    }
}

public struct MarkdownListItem: Equatable, Sendable, Decodable {
    /// `true`/`false` for a `- [x]` / `- [ ]` item; `nil` for an ordinary one.
    public let checked: Bool?
    public let blocks: [MarkdownBlock]

    public init(checked: Bool?, blocks: [MarkdownBlock]) {
        self.checked = checked
        self.blocks = blocks
    }
}

public enum MarkdownAlignment: String, Equatable, Sendable, Decodable {
    case left, center, right, none
}

public enum MarkdownInline: Equatable, Sendable, Decodable {
    case text(MarkdownRun)
    /// A person (`@`), a list (`#`) or a task (`!`), by id.
    case reference(MarkdownReference, label: String, id: String)
    case lineBreak

    private enum Keys: String, CodingKey { case kind, reference, label, id }

    public init(from decoder: Decoder) throws {
        let inline = try decoder.container(keyedBy: Keys.self)
        switch try inline.decode(String.self, forKey: .kind) {
        case "reference":
            self = .reference(
                try inline.decode(MarkdownReference.self, forKey: .reference),
                label: try inline.decode(String.self, forKey: .label),
                id: try inline.decode(String.self, forKey: .id))
        case "lineBreak":
            self = .lineBreak
        default:
            self = .text(try MarkdownRun(from: decoder))
        }
    }
}

/// One run of text and the marks on it.
public struct MarkdownRun: Equatable, Sendable, Decodable {
    public var text: String
    public var bold = false
    public var italic = false
    public var strike = false
    /// An inline code span.
    public var code = false
    /// An absolute `http`, `https` or `mailto` address, when the run is a link.
    public var link: String?

    public init(text: String, bold: Bool = false, italic: Bool = false, strike: Bool = false,
                code: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.strike = strike
        self.code = code
        self.link = link
    }
}

public enum MarkdownReference: String, Equatable, Sendable, Decodable {
    case user, list, task
}

extension CoreRules {
    /// Render `text` the way the web renders it. Never throws: text the core somehow cannot
    /// answer for comes back as one plain paragraph, because a message must never vanish.
    public static func markdown(_ text: String) -> [MarkdownBlock] {
        struct Request: Encodable {
            let kind = "renderMarkdown"
            let text: String
        }
        return (try? ask(Request(text: text), as: [MarkdownBlock].self))
            ?? [.paragraph([.text(MarkdownRun(text: text))])]
    }
}
